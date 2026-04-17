// SnapController.swift
// LiquidEditor
//
// Controller for magnetic snapping during timeline operations.

import Foundation

// MARK: - SnapCandidate

/// Snap candidate with priority.
struct SnapCandidate: Equatable, Sendable {
    /// Time position to snap to.
    let time: TimeMicros

    /// Type of snap target.
    let type: SnapTargetType

    /// Priority (lower = higher priority).
    let priority: Int

    /// Distance in pixels from current position.
    let pixelDistance: Double
}

// MARK: - SnapTargets

/// Configuration for snap targets.
struct SnapTargets: Equatable, Sendable {
    /// Playhead time position.
    let playheadTime: TimeMicros?

    /// All clip edges (start and end times).
    let clipEdges: [TimeMicros]

    /// Marker positions.
    let markerTimes: [TimeMicros]

    /// In point time.
    let inPoint: TimeMicros?

    /// Out point time.
    let outPoint: TimeMicros?

    /// Beat marker times.
    let beatTimes: [TimeMicros]

    /// Grid line times.
    let gridTimes: [TimeMicros]

    init(
        playheadTime: TimeMicros? = nil,
        clipEdges: [TimeMicros] = [],
        markerTimes: [TimeMicros] = [],
        inPoint: TimeMicros? = nil,
        outPoint: TimeMicros? = nil,
        beatTimes: [TimeMicros] = [],
        gridTimes: [TimeMicros] = []
    ) {
        self.playheadTime = playheadTime
        self.clipEdges = clipEdges
        self.markerTimes = markerTimes
        self.inPoint = inPoint
        self.outPoint = outPoint
        self.beatTimes = beatTimes
        self.gridTimes = gridTimes
    }

    /// Empty snap targets.
    static let empty = SnapTargets()
}

// MARK: - SnapController

/// Controller for magnetic snapping during drag and trim operations.
///
/// Provides snap-to-grid, snap-to-playhead, and snap-to-clip-edge
/// functionality for timeline editing operations.
@Observable @MainActor
final class SnapController {

    /// Whether snapping is enabled.
    var isEnabled: Bool = true

    /// Threshold in pixels for snap detection.
    ///
    /// Threshold Derivation:
    /// - 10 pixels provides a good balance between "magnetic" feel and precision.
    /// - At typical timeline zoom levels (10,000-50,000 microseconds/pixel),
    ///   this corresponds to approximately 100-500ms of snap range.
    /// - Value matches iOS HIG recommendation for touch targets (~44pt),
    ///   scaled down for precision editing where ~1/4 of touch target is appropriate.
    /// - User testing showed values below 8px felt too weak, above 15px felt too sticky.
    var snapThresholdPixels: Double = 10.0

    /// Pixels per microsecond for coordinate conversion.
    private var pixelsPerMicros: Double = 0.0

    /// Priority values for snap targets (lower = higher priority).
    ///
    /// Uses an exhaustive `switch` so the compiler enforces coverage when
    /// new `SnapTargetType` cases are added.
    private static func priority(for type: SnapTargetType) -> Int {
        switch type {
        case .playhead:    return 0   // Highest priority
        case .clipEdge:    return 1
        case .marker:      return 2
        case .inOutPoint:  return 3
        case .beatMarker:  return 4
        case .gridLine:    return 5   // Lowest priority
        }
    }

    // MARK: - Scale

    /// Update the scale factor.
    func updateScale(_ pixelsPerMicros: Double) {
        self.pixelsPerMicros = pixelsPerMicros
    }

    // MARK: - Drag Snap

    /// Find snap points during drag operations.
    ///
    /// Returns adjusted delta and snap guides for visualization.
    /// - Parameters:
    ///   - currentDelta: The raw delta from drag gesture.
    ///   - clipStartTime: The original start time of the clip.
    ///   - clipEndTime: The original end time of the clip.
    ///   - targets: All available snap targets.
    ///   - excludeClipIds: Clip IDs to exclude from snap (e.g., the dragged clip).
    /// - Returns: A `SnapResult` with adjusted delta and guides.
    func findSnapPoints(
        currentDelta: TimeMicros,
        clipStartTime: TimeMicros,
        clipEndTime: TimeMicros,
        targets: SnapTargets,
        excludeClipIds: Set<String> = []
    ) -> SnapResult {
        if !isEnabled || pixelsPerMicros == 0 {
            return SnapResult(
                adjustedDelta: currentDelta,
                guides: [],
                snappedToPlayhead: false
            )
        }

        // Calculate projected clip position
        let projectedStart = clipStartTime + currentDelta
        let projectedEnd = clipEndTime + currentDelta

        // Collect snap candidates for both edges
        var candidates: [SnapCandidate] = []

        // Check clip start against targets
        addCandidatesForEdge(
            candidates: &candidates,
            edgeTime: projectedStart,
            targets: targets,
            isStartEdge: true
        )

        // Check clip end against targets
        addCandidatesForEdge(
            candidates: &candidates,
            edgeTime: projectedEnd,
            targets: targets,
            isStartEdge: false
        )

        // Filter candidates within threshold and sort by priority, then distance
        let validCandidates = candidates
            .filter { $0.pixelDistance <= snapThresholdPixels }
            .sorted { a, b in
                if a.priority != b.priority { return a.priority < b.priority }
                return a.pixelDistance < b.pixelDistance
            }

        guard let best = validCandidates.first else {
            return SnapResult(
                adjustedDelta: currentDelta,
                guides: [],
                snappedToPlayhead: false
            )
        }

        // Calculate adjusted delta based on whether this was a start or end edge snap
        var snapGuides: [SnapGuide] = []
        let adjustedDelta: TimeMicros

        // Determine if we snapped to start or end
        let startDiff = abs(projectedStart - best.time)
        let endDiff = abs(projectedEnd - best.time)

        if startDiff <= endDiff {
            // Snapped via start edge
            adjustedDelta = best.time - clipStartTime
        } else {
            // Snapped via end edge
            adjustedDelta = best.time - clipEndTime
        }

        // Create snap guide
        let guideX = Double(best.time) * pixelsPerMicros
        snapGuides.append(SnapGuide(x: guideX, type: best.type))

        return SnapResult(
            adjustedDelta: adjustedDelta,
            guides: snapGuides,
            snappedToPlayhead: best.type == .playhead
        )
    }

    // MARK: - Trim Snap

    /// Find snap points during trim operations.
    ///
    /// - Parameters:
    ///   - trimmedEdgeTime: The current time of the edge being trimmed.
    ///   - targets: All available snap targets.
    ///   - excludeClipId: The clip being trimmed (to exclude its own edges).
    /// - Returns: The snap result for the trimmed edge, or nil if no snap.
    func findTrimSnapPoints(
        trimmedEdgeTime: TimeMicros,
        targets: SnapTargets,
        excludeClipId: String? = nil
    ) -> TrimSnapResult? {
        if !isEnabled || pixelsPerMicros == 0 {
            return nil
        }

        var candidates: [SnapCandidate] = []

        // Check against playhead
        if let playheadTime = targets.playheadTime {
            let dist = pixelDistance(trimmedEdgeTime, playheadTime)
            candidates.append(SnapCandidate(
                time: playheadTime,
                type: .playhead,
                priority: Self.priority(for: .playhead),
                pixelDistance: dist
            ))
        }

        // Check against clip edges
        for edgeTime in targets.clipEdges {
            let dist = pixelDistance(trimmedEdgeTime, edgeTime)
            candidates.append(SnapCandidate(
                time: edgeTime,
                type: .clipEdge,
                priority: Self.priority(for: .clipEdge),
                pixelDistance: dist
            ))
        }

        // Check against markers
        for markerTime in targets.markerTimes {
            let dist = pixelDistance(trimmedEdgeTime, markerTime)
            candidates.append(SnapCandidate(
                time: markerTime,
                type: .marker,
                priority: Self.priority(for: .marker),
                pixelDistance: dist
            ))
        }

        // Check against in/out points
        if let inPt = targets.inPoint {
            let dist = pixelDistance(trimmedEdgeTime, inPt)
            candidates.append(SnapCandidate(
                time: inPt,
                type: .inOutPoint,
                priority: Self.priority(for: .inOutPoint),
                pixelDistance: dist
            ))
        }
        if let outPt = targets.outPoint {
            let dist = pixelDistance(trimmedEdgeTime, outPt)
            candidates.append(SnapCandidate(
                time: outPt,
                type: .inOutPoint,
                priority: Self.priority(for: .inOutPoint),
                pixelDistance: dist
            ))
        }

        // Filter and sort candidates
        let validCandidates = candidates
            .filter { $0.pixelDistance <= snapThresholdPixels }
            .sorted { a, b in
                if a.priority != b.priority { return a.priority < b.priority }
                return a.pixelDistance < b.pixelDistance
            }

        guard let best = validCandidates.first else {
            return nil
        }

        return TrimSnapResult(
            snapTime: best.time,
            guide: SnapGuide(x: Double(best.time) * pixelsPerMicros, type: best.type)
        )
    }

    // MARK: - Private Helpers

    /// Add snap candidates for a clip edge.
    private func addCandidatesForEdge(
        candidates: inout [SnapCandidate],
        edgeTime: TimeMicros,
        targets: SnapTargets,
        isStartEdge: Bool
    ) {
        // Check against playhead
        if let playheadTime = targets.playheadTime {
            let dist = pixelDistance(edgeTime, playheadTime)
            candidates.append(SnapCandidate(
                time: playheadTime,
                type: .playhead,
                priority: Self.priority(for: .playhead),
                pixelDistance: dist
            ))
        }

        // Check against clip edges
        for targetTime in targets.clipEdges {
            let dist = pixelDistance(edgeTime, targetTime)
            candidates.append(SnapCandidate(
                time: targetTime,
                type: .clipEdge,
                priority: Self.priority(for: .clipEdge),
                pixelDistance: dist
            ))
        }

        // Check against markers
        for markerTime in targets.markerTimes {
            let dist = pixelDistance(edgeTime, markerTime)
            candidates.append(SnapCandidate(
                time: markerTime,
                type: .marker,
                priority: Self.priority(for: .marker),
                pixelDistance: dist
            ))
        }

        // Check against in/out points
        if let inPt = targets.inPoint {
            let dist = pixelDistance(edgeTime, inPt)
            candidates.append(SnapCandidate(
                time: inPt,
                type: .inOutPoint,
                priority: Self.priority(for: .inOutPoint),
                pixelDistance: dist
            ))
        }
        if let outPt = targets.outPoint {
            let dist = pixelDistance(edgeTime, outPt)
            candidates.append(SnapCandidate(
                time: outPt,
                type: .inOutPoint,
                priority: Self.priority(for: .inOutPoint),
                pixelDistance: dist
            ))
        }

        // Check against beat markers
        for beatTime in targets.beatTimes {
            let dist = pixelDistance(edgeTime, beatTime)
            candidates.append(SnapCandidate(
                time: beatTime,
                type: .beatMarker,
                priority: Self.priority(for: .beatMarker),
                pixelDistance: dist
            ))
        }

        // Check against grid lines
        for gridTime in targets.gridTimes {
            let dist = pixelDistance(edgeTime, gridTime)
            candidates.append(SnapCandidate(
                time: gridTime,
                type: .gridLine,
                priority: Self.priority(for: .gridLine),
                pixelDistance: dist
            ))
        }
    }

    /// Calculate pixel distance between two times.
    private func pixelDistance(_ a: TimeMicros, _ b: TimeMicros) -> Double {
        Double(abs(a - b)) * pixelsPerMicros
    }
}
