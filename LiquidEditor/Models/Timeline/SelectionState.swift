import Foundation
import CoreGraphics

// MARK: - SelectionMode

/// Selection mode determines current editing behavior.
enum SelectionMode: String, Codable, CaseIterable, Sendable {
    /// Normal selection mode -- select clips.
    case normal
    /// Range selection mode -- in/out point selection.
    case range
    /// Trimming clip head (left edge).
    case trimHead
    /// Trimming clip tail (right edge).
    case trimTail
    /// Slipping content within clip boundaries.
    case slip
    /// Sliding clip position (adjacent clips adjust).
    case slide
    /// Roll edit (adjust edit point between clips).
    case roll
    /// Marquee multi-selection.
    case marquee
}

// MARK: - SelectionState

/// Immutable selection state.
struct SelectionState: Codable, Equatable, Hashable, Sendable {
    /// Set of selected clip IDs.
    let selectedClipIds: Set<String>

    /// Primary selected clip ID (for multi-select operations).
    let primaryClipId: String?

    /// Selected marker ID.
    let selectedMarkerId: String?

    /// Selected transition ID.
    let selectedTransitionId: String?

    /// Selected keyframe ID.
    let selectedKeyframeId: String?

    /// In point for range selection.
    let inPoint: TimeMicros?

    /// Out point for range selection.
    let outPoint: TimeMicros?

    /// Current selection mode.
    let mode: SelectionMode

    /// Marquee selection start point (pixels).
    let marqueeStart: CGPoint?

    /// Marquee selection end point (pixels).
    let marqueeEnd: CGPoint?

    init(
        selectedClipIds: Set<String> = [],
        primaryClipId: String? = nil,
        selectedMarkerId: String? = nil,
        selectedTransitionId: String? = nil,
        selectedKeyframeId: String? = nil,
        inPoint: TimeMicros? = nil,
        outPoint: TimeMicros? = nil,
        mode: SelectionMode = .normal,
        marqueeStart: CGPoint? = nil,
        marqueeEnd: CGPoint? = nil
    ) {
        self.selectedClipIds = selectedClipIds
        self.primaryClipId = primaryClipId
        self.selectedMarkerId = selectedMarkerId
        self.selectedTransitionId = selectedTransitionId
        self.selectedKeyframeId = selectedKeyframeId
        self.inPoint = inPoint
        self.outPoint = outPoint
        self.mode = mode
        self.marqueeStart = marqueeStart
        self.marqueeEnd = marqueeEnd
    }

    /// Empty selection state.
    static let empty = SelectionState()

    // MARK: - Computed Properties

    /// Check if any clips are selected.
    var hasSelection: Bool { !selectedClipIds.isEmpty }

    /// Check if multiple clips are selected.
    var hasMultiSelection: Bool { selectedClipIds.count > 1 }

    /// Check if has range selection (in/out points).
    var hasRange: Bool { inPoint != nil && outPoint != nil }

    /// Get range duration.
    var rangeDuration: TimeMicros? {
        guard let inP = inPoint, let outP = outPoint else { return nil }
        return outP - inP
    }

    /// Get range as TimeRange.
    var rangeAsTimeRange: TimeRange? {
        guard let inP = inPoint, let outP = outPoint else { return nil }
        return TimeRange(inP, outP)
    }

    /// Number of selected clips.
    var selectionCount: Int { selectedClipIds.count }

    /// Check if currently in a trim mode.
    var isTrimming: Bool { mode == .trimHead || mode == .trimTail }

    /// Check if currently in marquee selection.
    var isMarqueeSelecting: Bool { mode == .marquee && marqueeStart != nil }

    /// Get marquee rect (if marquee selecting).
    var marqueeRect: CGRect? {
        guard let start = marqueeStart, let end = marqueeEnd else { return nil }
        let x = min(start.x, end.x)
        let y = min(start.y, end.y)
        let w = abs(end.x - start.x)
        let h = abs(end.y - start.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Selection Queries

    /// Check if a clip is selected.
    func isClipSelected(_ clipId: String) -> Bool { selectedClipIds.contains(clipId) }

    /// Check if a clip is the primary selection.
    func isPrimaryClip(_ clipId: String) -> Bool { primaryClipId == clipId }

    /// Check if a marker is selected.
    func isMarkerSelected(_ markerId: String) -> Bool { selectedMarkerId == markerId }

    /// Check if a transition is selected.
    func isTransitionSelected(_ transitionId: String) -> Bool { selectedTransitionId == transitionId }

    /// Check if a keyframe is selected.
    func isKeyframeSelected(_ keyframeId: String) -> Bool { selectedKeyframeId == keyframeId }

    // MARK: - State Updates

    /// Copy with updated values.
    func with(
        selectedClipIds: Set<String>? = nil,
        primaryClipId: String?? = nil,
        selectedMarkerId: String?? = nil,
        selectedTransitionId: String?? = nil,
        selectedKeyframeId: String?? = nil,
        inPoint: TimeMicros?? = nil,
        outPoint: TimeMicros?? = nil,
        mode: SelectionMode? = nil,
        marqueeStart: CGPoint?? = nil,
        marqueeEnd: CGPoint?? = nil
    ) -> SelectionState {
        SelectionState(
            selectedClipIds: selectedClipIds ?? self.selectedClipIds,
            primaryClipId: primaryClipId ?? self.primaryClipId,
            selectedMarkerId: selectedMarkerId ?? self.selectedMarkerId,
            selectedTransitionId: selectedTransitionId ?? self.selectedTransitionId,
            selectedKeyframeId: selectedKeyframeId ?? self.selectedKeyframeId,
            inPoint: inPoint ?? self.inPoint,
            outPoint: outPoint ?? self.outPoint,
            mode: mode ?? self.mode,
            marqueeStart: marqueeStart ?? self.marqueeStart,
            marqueeEnd: marqueeEnd ?? self.marqueeEnd
        )
    }

    // MARK: - Clip Selection Operations

    /// Select a single clip (clear other selections).
    func selectClip(_ clipId: String) -> SelectionState {
        SelectionState(
            selectedClipIds: [clipId],
            primaryClipId: clipId,
            mode: .normal
        )
    }

    /// Add clip to selection.
    func addClipToSelection(_ clipId: String) -> SelectionState {
        var newSelection = selectedClipIds
        newSelection.insert(clipId)
        return with(
            selectedClipIds: newSelection,
            primaryClipId: .some(clipId),
            mode: .normal
        )
    }

    /// Remove clip from selection.
    func removeClipFromSelection(_ clipId: String) -> SelectionState {
        var newSelection = selectedClipIds
        newSelection.remove(clipId)
        let newPrimary: String? = primaryClipId == clipId
            ? (newSelection.isEmpty ? nil : newSelection.first)
            : primaryClipId
        return with(
            selectedClipIds: newSelection,
            primaryClipId: .some(newPrimary)
        )
    }

    /// Toggle clip selection.
    func toggleClipSelection(_ clipId: String) -> SelectionState {
        if selectedClipIds.contains(clipId) {
            return removeClipFromSelection(clipId)
        } else {
            return addClipToSelection(clipId)
        }
    }

    /// Select multiple clips.
    func selectClips(_ clipIds: Set<String>, primaryId: String? = nil) -> SelectionState {
        with(
            selectedClipIds: clipIds,
            primaryClipId: .some(primaryId ?? clipIds.first),
            mode: .normal
        )
    }

    /// Clear clip selection.
    func clearClipSelection() -> SelectionState {
        with(selectedClipIds: [], primaryClipId: .some(nil))
    }

    // MARK: - Other Selection Operations

    /// Select a marker.
    func selectMarker(_ markerId: String) -> SelectionState {
        SelectionState(
            selectedMarkerId: markerId,
            mode: .normal
        )
    }

    /// Select a transition.
    func selectTransition(_ transitionId: String) -> SelectionState {
        SelectionState(
            selectedTransitionId: transitionId,
            mode: .normal
        )
    }

    /// Select a keyframe.
    func selectKeyframe(_ keyframeId: String) -> SelectionState {
        with(selectedKeyframeId: .some(keyframeId), mode: .normal)
    }

    /// Clear all selections.
    func clearAll() -> SelectionState {
        SelectionState()
    }

    // MARK: - Range Selection

    /// Set in point.
    func setInPoint(_ time: TimeMicros) -> SelectionState {
        with(inPoint: .some(time), mode: .range)
    }

    /// Set out point.
    func setOutPoint(_ time: TimeMicros) -> SelectionState {
        with(outPoint: .some(time), mode: .range)
    }

    /// Set both in and out points.
    func setRange(inTime: TimeMicros, outTime: TimeMicros) -> SelectionState {
        with(inPoint: .some(inTime), outPoint: .some(outTime), mode: .range)
    }

    /// Clear range selection.
    func clearRange() -> SelectionState {
        with(inPoint: .some(nil), outPoint: .some(nil), mode: .normal)
    }

    // MARK: - Mode Operations

    /// Enter trim head mode.
    func enterTrimHeadMode() -> SelectionState { with(mode: .trimHead) }

    /// Enter trim tail mode.
    func enterTrimTailMode() -> SelectionState { with(mode: .trimTail) }

    /// Enter slip mode.
    func enterSlipMode() -> SelectionState { with(mode: .slip) }

    /// Enter slide mode.
    func enterSlideMode() -> SelectionState { with(mode: .slide) }

    /// Enter roll mode.
    func enterRollMode() -> SelectionState { with(mode: .roll) }

    /// Exit special modes, return to normal.
    func exitSpecialMode() -> SelectionState {
        with(mode: .normal, marqueeStart: .some(nil), marqueeEnd: .some(nil))
    }

    // MARK: - Marquee Selection

    /// Start marquee selection.
    func startMarquee(_ start: CGPoint) -> SelectionState {
        with(mode: .marquee, marqueeStart: .some(start), marqueeEnd: .some(start))
    }

    /// Update marquee end point.
    func updateMarquee(_ end: CGPoint) -> SelectionState {
        with(marqueeEnd: .some(end))
    }

    /// End marquee selection.
    func endMarquee() -> SelectionState {
        with(mode: .normal, marqueeStart: .some(nil), marqueeEnd: .some(nil))
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case selectedClipIds, primaryClipId
        case selectedMarkerId, selectedTransitionId, selectedKeyframeId
        case inPoint, outPoint, mode
        case marqueeStartX, marqueeStartY, marqueeEndX, marqueeEndY
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedClipIds = try container.decodeIfPresent(Set<String>.self, forKey: .selectedClipIds) ?? []
        primaryClipId = try container.decodeIfPresent(String.self, forKey: .primaryClipId)
        selectedMarkerId = try container.decodeIfPresent(String.self, forKey: .selectedMarkerId)
        selectedTransitionId = try container.decodeIfPresent(String.self, forKey: .selectedTransitionId)
        selectedKeyframeId = try container.decodeIfPresent(String.self, forKey: .selectedKeyframeId)
        inPoint = try container.decodeIfPresent(TimeMicros.self, forKey: .inPoint)
        outPoint = try container.decodeIfPresent(TimeMicros.self, forKey: .outPoint)
        let modeStr = try container.decodeIfPresent(String.self, forKey: .mode) ?? "normal"
        mode = SelectionMode(rawValue: modeStr) ?? .normal

        if let sx = try container.decodeIfPresent(Double.self, forKey: .marqueeStartX),
           let sy = try container.decodeIfPresent(Double.self, forKey: .marqueeStartY) {
            marqueeStart = CGPoint(x: sx, y: sy)
        } else {
            marqueeStart = nil
        }

        if let ex = try container.decodeIfPresent(Double.self, forKey: .marqueeEndX),
           let ey = try container.decodeIfPresent(Double.self, forKey: .marqueeEndY) {
            marqueeEnd = CGPoint(x: ex, y: ey)
        } else {
            marqueeEnd = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedClipIds, forKey: .selectedClipIds)
        try container.encodeIfPresent(primaryClipId, forKey: .primaryClipId)
        try container.encodeIfPresent(selectedMarkerId, forKey: .selectedMarkerId)
        try container.encodeIfPresent(selectedTransitionId, forKey: .selectedTransitionId)
        try container.encodeIfPresent(selectedKeyframeId, forKey: .selectedKeyframeId)
        try container.encodeIfPresent(inPoint, forKey: .inPoint)
        try container.encodeIfPresent(outPoint, forKey: .outPoint)
        try container.encode(mode.rawValue, forKey: .mode)
        try container.encodeIfPresent(marqueeStart?.x, forKey: .marqueeStartX)
        try container.encodeIfPresent(marqueeStart?.y, forKey: .marqueeStartY)
        try container.encodeIfPresent(marqueeEnd?.x, forKey: .marqueeEndX)
        try container.encodeIfPresent(marqueeEnd?.y, forKey: .marqueeEndY)
    }
}
