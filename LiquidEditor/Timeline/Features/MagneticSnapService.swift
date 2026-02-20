// MagneticSnapService.swift
// LiquidEditor
//
// Magnetic snap service for timeline clip snapping.
// Detects snap points between clips, playhead, and markers.
// Provides configurable snap threshold and visual snap indicators.
//

import Foundation
import UIKit

// MARK: - SnapSource

/// Source of a snap point.
enum SnapSource: String, Sendable, CaseIterable {
    /// Snap to another clip's edge.
    case clipEdge
    /// Snap to the playhead position.
    case playhead
    /// Snap to a marker.
    case marker
    /// Snap to a grid line.
    case gridLine
}

// MARK: - SnapPoint

/// A detected snap point on the timeline.
struct SnapPoint: Equatable, Hashable, Sendable {
    /// Time position of the snap point (microseconds).
    let time: TimeMicros

    /// Source of the snap point.
    let source: SnapSource

    /// Optional label for the snap point.
    let label: String?

    init(time: TimeMicros, source: SnapSource, label: String? = nil) {
        self.time = time
        self.source = source
        self.label = label
    }

    static func == (lhs: SnapPoint, rhs: SnapPoint) -> Bool {
        lhs.time == rhs.time && lhs.source == rhs.source
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(time)
        hasher.combine(source)
    }
}

// MARK: - SnapDetectionResult

/// Result of a snap detection operation.
struct SnapDetectionResult: Equatable, Sendable {
    /// The snap point that was matched, or nil if no snap.
    let snapPoint: SnapPoint?

    /// The adjusted time after snapping.
    let adjustedTime: TimeMicros

    /// Whether a snap occurred.
    let didSnap: Bool

    /// The pixel distance to the snap point.
    let pixelDistance: Double

    init(
        snapPoint: SnapPoint? = nil,
        adjustedTime: TimeMicros,
        didSnap: Bool,
        pixelDistance: Double = 0
    ) {
        self.snapPoint = snapPoint
        self.adjustedTime = adjustedTime
        self.didSnap = didSnap
        self.pixelDistance = pixelDistance
    }

    /// No snap result.
    static func noSnap(_ time: TimeMicros) -> SnapDetectionResult {
        SnapDetectionResult(adjustedTime: time, didSnap: false)
    }
}

// MARK: - MagneticSnapConfig

/// Configuration for the magnetic snap service.
struct MagneticSnapConfig: Equatable, Sendable {
    /// Whether snapping is enabled.
    let isEnabled: Bool

    /// Snap threshold in pixels.
    let thresholdPixels: Double

    /// Snap threshold in microseconds (computed from pixels and zoom level).
    let thresholdMicros: TimeMicros

    /// Whether to snap to clip edges.
    let snapToClipEdges: Bool

    /// Whether to snap to playhead.
    let snapToPlayhead: Bool

    /// Whether to snap to markers.
    let snapToMarkers: Bool

    /// Whether to snap to grid lines.
    let snapToGrid: Bool

    init(
        isEnabled: Bool = true,
        thresholdPixels: Double = 10.0,
        thresholdMicros: TimeMicros = 100_000,
        snapToClipEdges: Bool = true,
        snapToPlayhead: Bool = true,
        snapToMarkers: Bool = true,
        snapToGrid: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.thresholdPixels = thresholdPixels
        self.thresholdMicros = thresholdMicros
        self.snapToClipEdges = snapToClipEdges
        self.snapToPlayhead = snapToPlayhead
        self.snapToMarkers = snapToMarkers
        self.snapToGrid = snapToGrid
    }

    static let defaults = MagneticSnapConfig()
    static let disabled = MagneticSnapConfig(isEnabled: false)

    /// Create a copy with updated zoom-based threshold.
    func withZoomLevel(_ microsPerPixel: Double) -> MagneticSnapConfig {
        MagneticSnapConfig(
            isEnabled: isEnabled,
            thresholdPixels: thresholdPixels,
            thresholdMicros: TimeMicros((thresholdPixels * microsPerPixel).rounded()),
            snapToClipEdges: snapToClipEdges,
            snapToPlayhead: snapToPlayhead,
            snapToMarkers: snapToMarkers,
            snapToGrid: snapToGrid
        )
    }

    func with(
        isEnabled: Bool? = nil,
        thresholdPixels: Double? = nil,
        thresholdMicros: TimeMicros? = nil,
        snapToClipEdges: Bool? = nil,
        snapToPlayhead: Bool? = nil,
        snapToMarkers: Bool? = nil,
        snapToGrid: Bool? = nil
    ) -> MagneticSnapConfig {
        MagneticSnapConfig(
            isEnabled: isEnabled ?? self.isEnabled,
            thresholdPixels: thresholdPixels ?? self.thresholdPixels,
            thresholdMicros: thresholdMicros ?? self.thresholdMicros,
            snapToClipEdges: snapToClipEdges ?? self.snapToClipEdges,
            snapToPlayhead: snapToPlayhead ?? self.snapToPlayhead,
            snapToMarkers: snapToMarkers ?? self.snapToMarkers,
            snapToGrid: snapToGrid ?? self.snapToGrid
        )
    }
}

// MARK: - MagneticSnapService

/// Service for detecting magnetic snap points between clips on the timeline.
///
/// Supports snapping to:
/// - Clip edges (start/end of other clips)
/// - Playhead position
/// - Markers
/// - Grid lines (optional)
///
/// Snap threshold is configurable in both pixels and time.
@Observable @MainActor
final class MagneticSnapService {

    /// Current configuration.
    private(set) var config: MagneticSnapConfig

    /// Creates a magnetic snap service with optional configuration.
    init(config: MagneticSnapConfig = .defaults) {
        self.config = config
    }

    /// Update configuration.
    func updateConfig(_ config: MagneticSnapConfig) {
        self.config = config
    }

    /// Toggle snap on/off.
    func toggle() {
        config = config.with(isEnabled: !config.isEnabled)
    }

    /// Whether snapping is currently enabled.
    var isEnabled: Bool { config.isEnabled }

    // MARK: - Collect Snap Points

    /// Collect all potential snap points from the current timeline state.
    ///
    /// - Parameters:
    ///   - clips: All clips on the timeline.
    ///   - playheadTime: Current playhead position (if snapping to playhead).
    ///   - markers: Timeline markers (if snapping to markers).
    ///   - excludeClipIds: Clip IDs to exclude (e.g., the clip being dragged).
    /// - Returns: List of snap points.
    func collectSnapPoints(
        clips: [TimelineClip],
        playheadTime: TimeMicros? = nil,
        markers: [TimelineMarker] = [],
        excludeClipIds: Set<String> = []
    ) -> [SnapPoint] {
        var points: [SnapPoint] = []

        // Collect clip edges
        if config.snapToClipEdges {
            for clip in clips {
                if excludeClipIds.contains(clip.id) { continue }

                points.append(SnapPoint(
                    time: clip.startTime,
                    source: .clipEdge,
                    label: "\(clip.label ?? clip.type.rawValue) start"
                ))
                points.append(SnapPoint(
                    time: clip.endTime,
                    source: .clipEdge,
                    label: "\(clip.label ?? clip.type.rawValue) end"
                ))
            }
        }

        // Collect playhead
        if config.snapToPlayhead, let playheadTime {
            points.append(SnapPoint(
                time: playheadTime,
                source: .playhead,
                label: "Playhead"
            ))
        }

        // Collect markers
        if config.snapToMarkers {
            for marker in markers {
                points.append(SnapPoint(
                    time: marker.time,
                    source: .marker,
                    label: marker.label
                ))
                if marker.isRange {
                    points.append(SnapPoint(
                        time: marker.endTime,
                        source: .marker,
                        label: "\(marker.label) end"
                    ))
                }
            }
        }

        return points
    }

    // MARK: - Detect Snap

    /// Detect the nearest snap point for a given time position.
    ///
    /// - Parameters:
    ///   - time: The time position to test.
    ///   - snapPoints: Available snap points (from `collectSnapPoints`).
    ///   - microsPerPixel: Current zoom level for pixel-distance conversion.
    /// - Returns: A `SnapDetectionResult` indicating whether a snap occurred.
    func detectSnap(
        time: TimeMicros,
        snapPoints: [SnapPoint],
        microsPerPixel: Double = 10000
    ) -> SnapDetectionResult {
        guard config.isEnabled, !snapPoints.isEmpty else {
            return .noSnap(time)
        }

        let threshold = TimeMicros((config.thresholdPixels * microsPerPixel).rounded())

        var bestSnap: SnapPoint?
        var bestDistance: TimeMicros = threshold + 1

        for point in snapPoints {
            let distance = abs(point.time - time)
            if distance <= threshold && distance < bestDistance {
                bestSnap = point
                bestDistance = distance
            }
        }

        guard let snap = bestSnap else {
            return .noSnap(time)
        }

        let pixelDist = microsPerPixel > 0 ? Double(bestDistance) / microsPerPixel : 0.0

        // Fire haptic feedback on snap.
        UISelectionFeedbackGenerator().selectionChanged()

        return SnapDetectionResult(
            snapPoint: snap,
            adjustedTime: snap.time,
            didSnap: true,
            pixelDistance: pixelDist
        )
    }

    // MARK: - Detect Clip Snap

    /// Detect snap for a clip being dragged, checking both start and end edges.
    ///
    /// Returns the best snap result considering both the start and end
    /// of the moving clip.
    func detectClipSnap(
        clipStartTime: TimeMicros,
        clipDuration: TimeMicros,
        snapPoints: [SnapPoint],
        microsPerPixel: Double = 10000
    ) -> SnapDetectionResult {
        guard config.isEnabled, !snapPoints.isEmpty else {
            return .noSnap(clipStartTime)
        }

        let startResult = detectSnap(
            time: clipStartTime,
            snapPoints: snapPoints,
            microsPerPixel: microsPerPixel
        )

        let endResult = detectSnap(
            time: clipStartTime + clipDuration,
            snapPoints: snapPoints,
            microsPerPixel: microsPerPixel
        )

        // Return the closer snap
        if !startResult.didSnap && !endResult.didSnap {
            return .noSnap(clipStartTime)
        }

        if startResult.didSnap && !endResult.didSnap {
            return startResult
        }

        if !startResult.didSnap && endResult.didSnap {
            // Adjust so the snap applies to the clip start
            return SnapDetectionResult(
                snapPoint: endResult.snapPoint,
                adjustedTime: endResult.adjustedTime - clipDuration,
                didSnap: true,
                pixelDistance: endResult.pixelDistance
            )
        }

        // Both snapped - pick the closer one
        if startResult.pixelDistance <= endResult.pixelDistance {
            return startResult
        }

        return SnapDetectionResult(
            snapPoint: endResult.snapPoint,
            adjustedTime: endResult.adjustedTime - clipDuration,
            didSnap: true,
            pixelDistance: endResult.pixelDistance
        )
    }
}
