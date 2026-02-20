import Foundation
import CoreGraphics

// ============================================================================
// MARK: - Trim Edge
// ============================================================================

/// Edge being trimmed.
enum TrimEdge: String, Codable, CaseIterable, Sendable {
    case left
    case right
}

// ============================================================================
// MARK: - Snap System
// ============================================================================

/// Type of snap target.
enum SnapTargetType: String, Codable, CaseIterable, Sendable {
    case playhead
    case clipEdge
    case marker
    case inOutPoint
    case beatMarker
    case gridLine
}

/// Snap guide for visualization.
struct SnapGuide: Equatable, Sendable {
    /// X position in pixels.
    let x: Double

    /// Type of snap target.
    let type: SnapTargetType
}

/// Result of snap calculation.
struct SnapResult: Equatable, Sendable {
    /// Adjusted time delta after snapping.
    let adjustedDelta: TimeMicros

    /// Snap guides to display.
    let guides: [SnapGuide]

    /// Whether snapped to playhead.
    let snappedToPlayhead: Bool
}

/// Trim snap result.
struct TrimSnapResult: Equatable, Sendable {
    /// Snapped time position.
    let snapTime: TimeMicros

    /// Snap guide to display.
    let guide: SnapGuide
}

// ============================================================================
// MARK: - Hit Testing (Edit Model)
// ============================================================================

/// Type of hit target (edit-model variant).
///
/// The interactive gesture hit-testing system uses `HitTestType`
/// and `HitTestResult` from `HitTesting.swift` instead.
enum EditHitType: String, Codable, CaseIterable, Sendable {
    case playhead
    case ruler
    case clip
    case trimHandle
    case transition
    case marker
    case keyframe
    case empty
}

/// Result of hit testing (edit-model variant).
///
/// The interactive gesture hit-testing system uses `HitTestResult`
/// from `HitTesting.swift` instead. This type is used for
/// simple edit-model operations.
struct EditHitTestResult: Equatable, Sendable {
    /// Type of hit.
    let type: EditHitType

    /// Clip ID (if applicable).
    let clipId: String?

    /// Marker ID (if applicable).
    let markerId: String?

    /// Transition ID (if applicable).
    let transitionId: String?

    /// Keyframe ID (if applicable).
    let keyframeId: String?

    /// Trim edge (if applicable).
    let trimEdge: TrimEdge?

    init(
        type: EditHitType,
        clipId: String? = nil,
        markerId: String? = nil,
        transitionId: String? = nil,
        keyframeId: String? = nil,
        trimEdge: TrimEdge? = nil
    ) {
        self.type = type
        self.clipId = clipId
        self.markerId = markerId
        self.transitionId = transitionId
        self.keyframeId = keyframeId
        self.trimEdge = trimEdge
    }

    /// Empty space hit.
    static let empty = EditHitTestResult(type: .empty)

    /// Playhead hit.
    static let playhead = EditHitTestResult(type: .playhead)

    /// Ruler hit.
    static let ruler = EditHitTestResult(type: .ruler)

    /// Clip hit.
    static func clip(_ clipId: String) -> EditHitTestResult {
        EditHitTestResult(type: .clip, clipId: clipId)
    }

    /// Trim handle hit.
    static func trimHandle(_ clipId: String, edge: TrimEdge) -> EditHitTestResult {
        EditHitTestResult(type: .trimHandle, clipId: clipId, trimEdge: edge)
    }

    /// Marker hit.
    static func marker(_ markerId: String) -> EditHitTestResult {
        EditHitTestResult(type: .marker, markerId: markerId)
    }

    /// Transition hit.
    static func transition(_ transitionId: String) -> EditHitTestResult {
        EditHitTestResult(type: .transition, transitionId: transitionId)
    }

    /// Keyframe hit.
    static func keyframe(_ keyframeId: String) -> EditHitTestResult {
        EditHitTestResult(type: .keyframe, keyframeId: keyframeId)
    }
}

// ============================================================================
// MARK: - Drag Operations (Edit Model)
// ============================================================================

/// State during clip drag operation (edit-model variant).
///
/// The interactive gesture drag system uses `DragState`
/// from `DragController.swift` instead.
struct EditDragState: Equatable, Sendable {
    /// Clips being dragged.
    let clips: [TimelineClip]

    /// Primary clip ID (touch target).
    let primaryClipId: String

    /// Original positions of all dragged clips.
    let originalPositions: [String: TimeMicros]

    /// Original track IDs of all dragged clips.
    let originalTrackIds: [String: String]

    /// Offset from touch to clip start (in microseconds).
    let touchOffsetMicros: TimeMicros

    /// Current target track ID.
    let currentTrackId: String
}

/// Preview of single clip during drag (edit-model variant).
struct EditClipPreview: Equatable, Sendable {
    /// Original clip.
    let originalClip: TimelineClip

    /// Preview start time.
    let previewStartTime: TimeMicros

    /// Preview track ID.
    let previewTrackId: String

    /// Preview end time.
    var previewEndTime: TimeMicros {
        previewStartTime + originalClip.duration
    }
}

/// Preview of drag result (edit-model variant).
///
/// The interactive gesture drag system uses `DragPreview`
/// from `DragController.swift` instead.
struct EditDragPreview: Equatable, Sendable {
    /// Preview of each clip's new position.
    let clips: [EditClipPreview]

    /// Active snap guides to display.
    let snapGuides: [SnapGuide]

    /// Whether the drop position is valid.
    let isValid: Bool

    /// Error message if invalid.
    let errorMessage: String?

    init(
        clips: [EditClipPreview],
        snapGuides: [SnapGuide],
        isValid: Bool,
        errorMessage: String? = nil
    ) {
        self.clips = clips
        self.snapGuides = snapGuides
        self.isValid = isValid
        self.errorMessage = errorMessage
    }

    /// Empty preview.
    static let empty = EditDragPreview(
        clips: [],
        snapGuides: [],
        isValid: false
    )
}

/// Clip move operation for applying changes.
struct ClipMove: Equatable, Sendable {
    /// Clip ID.
    let clipId: String

    /// New start time.
    let newStartTime: TimeMicros

    /// New track ID.
    let newTrackId: String
}

// ============================================================================
// MARK: - Trim Operations (Edit Model)
// ============================================================================

/// State during trim operation (edit-model variant).
///
/// The interactive gesture trim system uses `TrimState`
/// from `TrimController.swift` instead.
struct EditTrimState: Equatable, Sendable {
    /// Clip being trimmed.
    let clip: TimelineClip

    /// Edge being trimmed.
    let edge: TrimEdge

    /// Original start time for reset.
    let originalStartTime: TimeMicros

    /// Original duration for reset.
    let originalDuration: TimeMicros

    /// Original source in point for reset.
    let originalSourceIn: TimeMicros

    /// Original source out point for reset.
    let originalSourceOut: TimeMicros
}

/// Preview of trim result (edit-model variant).
///
/// Used by `RippleTrimController` for edit-model trim operations.
/// The interactive gesture trim system uses `TrimPreview`
/// from `TrimController.swift` instead.
struct EditTrimPreview: Equatable, Sendable {
    /// Clip ID.
    let clipId: String

    /// New start time.
    let newStartTime: TimeMicros

    /// New duration.
    let newDuration: TimeMicros

    /// New source in point.
    let newSourceIn: TimeMicros

    /// New source out point.
    let newSourceOut: TimeMicros

    /// Snap guide (if snapped).
    let snapGuide: SnapGuide?

    /// Amount trimmed.
    let trimmedDelta: TimeMicros

    /// Ripple effects on subsequent clips.
    let rippleClips: [RipplePreview]?

    /// Create a copy with updated ripple clips.
    func with(rippleClips: [RipplePreview]?) -> EditTrimPreview {
        EditTrimPreview(
            clipId: clipId,
            newStartTime: newStartTime,
            newDuration: newDuration,
            newSourceIn: newSourceIn,
            newSourceOut: newSourceOut,
            snapGuide: snapGuide,
            trimmedDelta: trimmedDelta,
            rippleClips: rippleClips
        )
    }

    /// Empty preview.
    static func empty() -> EditTrimPreview {
        EditTrimPreview(
            clipId: "", newStartTime: 0, newDuration: 0,
            newSourceIn: 0, newSourceOut: 0, snapGuide: nil,
            trimmedDelta: 0, rippleClips: nil
        )
    }
}

/// Ripple effect on subsequent clips.
struct RipplePreview: Equatable, Sendable {
    /// Clip ID.
    let clipId: String

    /// New start time.
    let newStartTime: TimeMicros
}

// ============================================================================
// MARK: - Roll Operations
// ============================================================================

/// State during roll edit operation.
struct RollState: Equatable, Sendable {
    /// Clip before the edit point.
    let leftClip: TimelineClip

    /// Clip after the edit point.
    let rightClip: TimelineClip

    /// Original edit point time.
    let originalEditPoint: TimeMicros
}

/// Preview of roll edit result.
struct RollPreview: Equatable, Sendable {
    /// Left clip ID.
    let leftClipId: String

    /// Right clip ID.
    let rightClipId: String

    /// Edit point time.
    let editPoint: TimeMicros

    /// New duration for left clip.
    let leftNewDuration: TimeMicros

    /// New start time for right clip.
    let rightNewStartTime: TimeMicros

    /// New duration for right clip.
    let rightNewDuration: TimeMicros

    /// Empty preview.
    static func empty() -> RollPreview {
        RollPreview(
            leftClipId: "", rightClipId: "", editPoint: 0,
            leftNewDuration: 0, rightNewStartTime: 0, rightNewDuration: 0
        )
    }
}

// ============================================================================
// MARK: - Slip Operations
// ============================================================================

/// State during slip operation.
struct SlipState: Equatable, Sendable {
    /// Clip being slipped.
    let clip: TimelineClip

    /// Original source in point.
    let originalSourceIn: TimeMicros

    /// Original source out point.
    let originalSourceOut: TimeMicros
}

/// Preview of slip result.
struct SlipPreview: Equatable, Sendable {
    /// Clip ID.
    let clipId: String

    /// New source in point.
    let newSourceIn: TimeMicros

    /// New source out point.
    let newSourceOut: TimeMicros

    /// Start time (unchanged).
    let startTime: TimeMicros

    /// Duration (unchanged).
    let duration: TimeMicros

    /// Empty preview.
    static func empty() -> SlipPreview {
        SlipPreview(clipId: "", newSourceIn: 0, newSourceOut: 0, startTime: 0, duration: 0)
    }
}

// ============================================================================
// MARK: - Slide Operations
// ============================================================================

/// State during slide operation.
struct SlideState: Equatable, Sendable {
    /// Clip being slid.
    let clip: TimelineClip

    /// Adjacent clip on the left (if any).
    let leftClip: TimelineClip?

    /// Adjacent clip on the right (if any).
    let rightClip: TimelineClip?

    /// Original start time.
    let originalStartTime: TimeMicros
}

/// Preview of slide result.
struct SlidePreview: Equatable, Sendable {
    /// Clip ID.
    let clipId: String

    /// New start time.
    let newStartTime: TimeMicros

    /// New duration for left adjacent clip.
    let leftClipNewDuration: TimeMicros?

    /// New start time for right adjacent clip.
    let rightClipNewStartTime: TimeMicros?

    /// Empty preview.
    static func empty() -> SlidePreview {
        SlidePreview(clipId: "", newStartTime: 0, leftClipNewDuration: nil, rightClipNewStartTime: nil)
    }
}

// ============================================================================
// MARK: - Split Operations
// ============================================================================

/// Individual clip split result.
struct SplitClipResult: Equatable, Sendable {
    /// Original clip ID.
    let originalClipId: String

    /// Left clip (before split point).
    let leftClip: TimelineClip

    /// Right clip (after split point).
    let rightClip: TimelineClip
}

/// Result of split operation.
struct SplitResult: Equatable, Sendable {
    /// Split results for each affected clip.
    let clips: [SplitClipResult]
}
