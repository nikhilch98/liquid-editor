import Foundation

// MARK: - TransitionCategory

/// Category grouping for transition browser UI.
enum TransitionCategory: String, Codable, CaseIterable, Sendable {
    /// Cross dissolve, dip, fade to black/white.
    case basic
    /// Wipe (directional, clock, iris).
    case wipe
    /// Slide, push, slide over, slide under.
    case slide
    /// Zoom in, zoom out.
    case zoom
    /// Blur, rotation, page curl.
    case special

    /// Display name for UI.
    var displayName: String {
        switch self {
        case .basic: "Basic"
        case .wipe: "Wipe"
        case .slide: "Slide"
        case .zoom: "Zoom"
        case .special: "Special"
        }
    }

    /// All transition types in this category.
    var types: [TransitionType] {
        TransitionType.allCases.filter { $0.category == self }
    }
}

// MARK: - TransitionType

/// Type of transition effect.
enum TransitionType: String, Codable, CaseIterable, Sendable {
    // Basic
    case crossDissolve
    case crossfade
    case dip
    case fadeToBlack
    case fadeToWhite

    // Wipe
    case wipe
    case wipeClock
    case wipeIris

    // Slide
    case slide
    case push
    case slideOver
    case slideUnder

    // Zoom
    case zoom
    case zoomIn
    case zoomOut

    // Special
    case blur
    case rotation
    case pageCurl
    case custom

    /// Display name for UI.
    var displayName: String {
        switch self {
        case .crossDissolve: "Cross Dissolve"
        case .crossfade: "Crossfade"
        case .dip: "Dip to Black"
        case .fadeToBlack: "Fade to Black"
        case .fadeToWhite: "Fade to White"
        case .wipe: "Wipe"
        case .wipeClock: "Clock Wipe"
        case .wipeIris: "Iris Wipe"
        case .slide: "Slide"
        case .push: "Push"
        case .slideOver: "Slide Over"
        case .slideUnder: "Slide Under"
        case .zoom: "Zoom"
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        case .blur: "Blur"
        case .rotation: "Rotation"
        case .pageCurl: "Page Curl"
        case .custom: "Custom"
        }
    }

    /// Category for browser grouping.
    var category: TransitionCategory {
        switch self {
        case .crossDissolve, .crossfade, .dip, .fadeToBlack, .fadeToWhite:
            return .basic
        case .wipe, .wipeClock, .wipeIris:
            return .wipe
        case .slide, .push, .slideOver, .slideUnder:
            return .slide
        case .zoom, .zoomIn, .zoomOut:
            return .zoom
        case .blur, .rotation, .pageCurl, .custom:
            return .special
        }
    }

    /// Default duration for this transition type (microseconds).
    var defaultDuration: TimeMicros {
        switch self {
        case .crossDissolve: 500_000
        case .crossfade: 500_000
        case .dip: 1_000_000
        case .fadeToBlack: 1_000_000
        case .fadeToWhite: 1_000_000
        case .wipe: 500_000
        case .wipeClock: 750_000
        case .wipeIris: 500_000
        case .slide: 500_000
        case .push: 500_000
        case .slideOver: 500_000
        case .slideUnder: 500_000
        case .zoom: 500_000
        case .zoomIn: 500_000
        case .zoomOut: 500_000
        case .blur: 750_000
        case .rotation: 600_000
        case .pageCurl: 800_000
        case .custom: 500_000
        }
    }

    /// Whether this type supports direction parameter.
    var supportsDirection: Bool {
        switch self {
        case .wipe, .slide, .push, .slideOver, .slideUnder: true
        default: false
        }
    }

    /// Whether this type supports color parameter.
    var supportsColor: Bool {
        switch self {
        case .dip, .fadeToBlack, .fadeToWhite: true
        default: false
        }
    }

    /// Whether this type supports softness parameter.
    var supportsSoftness: Bool {
        switch self {
        case .wipe, .wipeClock, .wipeIris: true
        default: false
        }
    }

    /// Whether this type requires two simultaneous video frames.
    var requiresDualFrames: Bool {
        self != .crossfade
    }

    /// Whether this transition type supports audio.
    var supportsAudio: Bool {
        self == .crossfade
    }

    /// Whether this transition type supports video.
    var supportsVideo: Bool {
        self != .crossfade
    }

    /// SF Symbol name for native iOS display.
    var sfSymbolName: String {
        switch self {
        case .crossDissolve: "square.on.square"
        case .crossfade: "waveform"
        case .dip: "square.fill"
        case .fadeToBlack: "moon.fill"
        case .fadeToWhite: "sun.max.fill"
        case .wipe: "arrow.right"
        case .wipeClock: "clock"
        case .wipeIris: "circle"
        case .slide: "arrow.right.square"
        case .push: "arrow.right.circle"
        case .slideOver: "arrow.right.square.fill"
        case .slideUnder: "arrow.left.square"
        case .zoom: "plus.magnifyingglass"
        case .zoomIn: "plus.magnifyingglass"
        case .zoomOut: "minus.magnifyingglass"
        case .blur: "drop"
        case .rotation: "arrow.triangle.2.circlepath"
        case .pageCurl: "book"
        case .custom: "sparkles"
        }
    }
}

// MARK: - TransitionAlignment

/// Alignment of transition relative to edit point.
enum TransitionAlignment: String, Codable, CaseIterable, Sendable {
    /// Transition is centered on the cut.
    case centerOnCut
    /// Transition starts at the cut.
    case startAtCut
    /// Transition ends at the cut.
    case endAtCut
}

// MARK: - TransitionDirection

/// Direction of wipe/slide transitions.
enum TransitionDirection: String, Codable, CaseIterable, Sendable {
    case left
    case right
    case up
    case down
}

// MARK: - EasingCurve

/// Named easing curves for transitions.
enum EasingCurve: String, Codable, CaseIterable, Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case fastOutSlowIn
    case decelerate
    case bounceOut
    case elasticOut
}

// MARK: - ClipTransition

/// Immutable clip transition.
struct ClipTransition: Codable, Equatable, Hashable, Sendable {
    /// Unique transition identifier.
    let id: String

    /// ID of the clip before the transition.
    let leftClipId: String

    /// ID of the clip after the transition.
    let rightClipId: String

    /// Track ID this transition belongs to.
    let trackId: String

    /// Type of transition effect.
    let type: TransitionType

    /// Duration of the transition (microseconds).
    let duration: TimeMicros

    /// Alignment relative to edit point.
    let alignment: TransitionAlignment

    /// Edit point time (where clips meet).
    let editPointTime: TimeMicros

    /// Direction for directional transitions.
    let direction: TransitionDirection

    /// Easing curve for the transition.
    let easing: EasingCurve

    /// Custom parameters for the transition effect.
    let parameters: [String: String]

    /// Minimum transition duration (~2 frames at 30fps).
    static let minDuration: TimeMicros = 66_666

    /// Maximum transition duration (5 seconds).
    static let maxDuration: TimeMicros = 5_000_000

    init(
        id: String,
        leftClipId: String,
        rightClipId: String,
        trackId: String,
        type: TransitionType,
        duration: TimeMicros,
        alignment: TransitionAlignment = .centerOnCut,
        editPointTime: TimeMicros,
        direction: TransitionDirection = .left,
        easing: EasingCurve = .easeInOut,
        parameters: [String: String] = [:]
    ) {
        self.id = id
        self.leftClipId = leftClipId
        self.rightClipId = rightClipId
        self.trackId = trackId
        self.type = type
        self.duration = duration
        self.alignment = alignment
        self.editPointTime = editPointTime
        self.direction = direction
        self.easing = easing
        self.parameters = parameters
    }

    // MARK: - Computed Properties

    /// Calculate transition time range on timeline.
    var timeRange: TimeRange {
        switch alignment {
        case .centerOnCut:
            let halfDuration = duration / 2
            return TimeRange(editPointTime - halfDuration, editPointTime + halfDuration)
        case .startAtCut:
            return TimeRange(editPointTime, editPointTime + duration)
        case .endAtCut:
            return TimeRange(editPointTime - duration, editPointTime)
        }
    }

    /// Start time of transition.
    var startTime: TimeMicros { timeRange.start }

    /// End time of transition.
    var endTime: TimeMicros { timeRange.end }

    /// How much overlap is required from left clip.
    var leftOverlapRequired: TimeMicros {
        switch alignment {
        case .centerOnCut: duration / 2
        case .startAtCut: 0
        case .endAtCut: duration
        }
    }

    /// How much overlap is required from right clip.
    var rightOverlapRequired: TimeMicros {
        switch alignment {
        case .centerOnCut: duration / 2
        case .startAtCut: duration
        case .endAtCut: 0
        }
    }

    // MARK: - Copy With

    /// Create a copy with updated values.
    func with(
        id: String? = nil,
        leftClipId: String? = nil,
        rightClipId: String? = nil,
        trackId: String? = nil,
        type: TransitionType? = nil,
        duration: TimeMicros? = nil,
        alignment: TransitionAlignment? = nil,
        editPointTime: TimeMicros? = nil,
        direction: TransitionDirection? = nil,
        easing: EasingCurve? = nil,
        parameters: [String: String]? = nil
    ) -> ClipTransition {
        ClipTransition(
            id: id ?? self.id,
            leftClipId: leftClipId ?? self.leftClipId,
            rightClipId: rightClipId ?? self.rightClipId,
            trackId: trackId ?? self.trackId,
            type: type ?? self.type,
            duration: duration ?? self.duration,
            alignment: alignment ?? self.alignment,
            editPointTime: editPointTime ?? self.editPointTime,
            direction: direction ?? self.direction,
            easing: easing ?? self.easing,
            parameters: parameters ?? self.parameters
        )
    }

    /// Change duration (clamped).
    func withDuration(_ newDuration: TimeMicros) -> ClipTransition {
        with(duration: min(max(newDuration, ClipTransition.minDuration), ClipTransition.maxDuration))
    }

    /// Change type.
    func withType(_ newType: TransitionType) -> ClipTransition {
        with(type: newType)
    }

    /// Change alignment.
    func withAlignment(_ newAlignment: TransitionAlignment) -> ClipTransition {
        with(alignment: newAlignment)
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: ClipTransition, rhs: ClipTransition) -> Bool {
        lhs.id == rhs.id &&
        lhs.leftClipId == rhs.leftClipId &&
        lhs.rightClipId == rhs.rightClipId &&
        lhs.trackId == rhs.trackId &&
        lhs.type == rhs.type &&
        lhs.duration == rhs.duration &&
        lhs.alignment == rhs.alignment &&
        lhs.editPointTime == rhs.editPointTime &&
        lhs.direction == rhs.direction
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(leftClipId)
        hasher.combine(rightClipId)
        hasher.combine(trackId)
        hasher.combine(type)
        hasher.combine(duration)
        hasher.combine(alignment)
        hasher.combine(editPointTime)
        hasher.combine(direction)
    }
}
