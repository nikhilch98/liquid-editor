// TrimController.swift
// LiquidEditor
//
// Head/tail trimming controller with source bounds checking,
// minimum duration enforcement, collision prevention, and haptic feedback.
//

import Foundation
import CoreGraphics
import UIKit

// MARK: - TrimType

/// Type of trim operation.
enum TrimType: String, Sendable, Equatable {
    /// Trimming the head (left edge, start time).
    case head
    /// Trimming the tail (right edge, end time).
    case tail
}

// MARK: - TrimStateType

/// State of a trim operation.
enum TrimStateType: String, Sendable, Equatable {
    /// No trim in progress.
    case idle
    /// Trim started but not moved significantly.
    case pending
    /// Actively trimming.
    case trimming
    /// Trim completed successfully.
    case completed
    /// Trim cancelled.
    case cancelled
}

// MARK: - TrimPreview

/// Preview information for a trim operation.
struct TrimPreview: Sendable, Equatable {
    /// Original clip being trimmed.
    let originalClip: TimelineClip
    /// Previewed clip with trim applied.
    let previewClip: TimelineClip
    /// Type of trim (head or tail).
    let trimType: TrimType
    /// Time delta applied to the edge.
    let timeDelta: TimeMicros
    /// Whether this trim position is valid.
    let isValid: Bool
    /// Reason if trim position is invalid.
    let invalidReason: String?
    /// Whether we hit the source start bound.
    let atSourceStart: Bool
    /// Whether we hit the source end bound.
    let atSourceEnd: Bool
    /// Whether we hit minimum duration.
    let atMinDuration: Bool
    /// Snapped time if snapping occurred.
    let snappedTime: TimeMicros?

    init(
        originalClip: TimelineClip,
        previewClip: TimelineClip,
        trimType: TrimType,
        timeDelta: TimeMicros,
        isValid: Bool = true,
        invalidReason: String? = nil,
        atSourceStart: Bool = false,
        atSourceEnd: Bool = false,
        atMinDuration: Bool = false,
        snappedTime: TimeMicros? = nil
    ) {
        self.originalClip = originalClip
        self.previewClip = previewClip
        self.trimType = trimType
        self.timeDelta = timeDelta
        self.isValid = isValid
        self.invalidReason = invalidReason
        self.atSourceStart = atSourceStart
        self.atSourceEnd = atSourceEnd
        self.atMinDuration = atMinDuration
        self.snappedTime = snappedTime
    }

    /// Empty preview.
    static let empty = TrimPreview(
        originalClip: .placeholder,
        previewClip: .placeholder,
        trimType: .head,
        timeDelta: 0,
        isValid: false
    )

    /// Duration change from original.
    var durationDelta: TimeMicros { previewClip.duration - originalClip.duration }

    /// Whether any bound was hit.
    var atBound: Bool { atSourceStart || atSourceEnd || atMinDuration }

    /// Whether snapping is active.
    var hasSnap: Bool { snappedTime != nil }
}

// MARK: - TrimState

/// State of an ongoing trim operation.
struct TrimState: Sendable, Equatable {
    /// Current state type.
    let type: TrimStateType
    /// Clip being trimmed.
    let clipId: String
    /// Type of trim.
    let trimType: TrimType
    /// Initial pointer position.
    let startPosition: CGPoint
    /// Current pointer position.
    let currentPosition: CGPoint
    /// Initial time at trim edge.
    let startEdgeTime: TimeMicros
    /// Current preview.
    let preview: TrimPreview
    /// Whether the trim crossed the movement threshold.
    let exceededThreshold: Bool

    /// Idle state.
    static let idle = TrimState(
        type: .idle,
        clipId: "",
        trimType: .head,
        startPosition: .zero,
        currentPosition: .zero,
        startEdgeTime: 0,
        preview: .empty,
        exceededThreshold: false
    )

    /// Whether a trim is in progress.
    var isTrimming: Bool { type == .trimming || type == .pending }

    /// Whether the trim has moved significantly.
    var hasMoved: Bool { exceededThreshold }

    /// Create copy with updated values.
    func with(
        type: TrimStateType? = nil,
        clipId: String? = nil,
        trimType: TrimType? = nil,
        startPosition: CGPoint? = nil,
        currentPosition: CGPoint? = nil,
        startEdgeTime: TimeMicros? = nil,
        preview: TrimPreview? = nil,
        exceededThreshold: Bool? = nil
    ) -> TrimState {
        TrimState(
            type: type ?? self.type,
            clipId: clipId ?? self.clipId,
            trimType: trimType ?? self.trimType,
            startPosition: startPosition ?? self.startPosition,
            currentPosition: currentPosition ?? self.currentPosition,
            startEdgeTime: startEdgeTime ?? self.startEdgeTime,
            preview: preview ?? self.preview,
            exceededThreshold: exceededThreshold ?? self.exceededThreshold
        )
    }
}

// MARK: - TrimValidation (internal)

/// Validation result for trim operations.
private struct TrimValidation {
    let isValid: Bool
    let reason: String?
    let atSourceStart: Bool
    let atSourceEnd: Bool
    let atMinDuration: Bool

    init(
        isValid: Bool,
        reason: String? = nil,
        atSourceStart: Bool = false,
        atSourceEnd: Bool = false,
        atMinDuration: Bool = false
    ) {
        self.isValid = isValid
        self.reason = reason
        self.atSourceStart = atSourceStart
        self.atSourceEnd = atSourceEnd
        self.atMinDuration = atMinDuration
    }
}

// MARK: - TimelineClip placeholder

extension TimelineClip {
    /// Placeholder clip for empty trim previews.
    static let placeholder = TimelineClip(
        id: "",
        trackId: "",
        type: .gap,
        startTime: 0,
        duration: 0
    )
}

// MARK: - TrimController

/// Controller for clip trim operations.
///
/// Manages trim state with proper bounds checking and validation.
@Observable @MainActor
final class TrimController {

    // MARK: - Constants

    /// Movement threshold before trim starts (pixels).
    static let trimThreshold: CGFloat = 4.0

    /// Snap distance in pixels.
    static let snapDistance: CGFloat = 10.0

    // MARK: - State

    /// Current trim state.
    private(set) var state: TrimState = .idle

    /// All clips for collision detection.
    private var allClips: [TimelineClip] = []

    /// Current viewport state.
    private var viewport: ViewportState = .initial()

    /// Snap targets for trimming.
    private var snapTargets: [TimeMicros] = []

    /// Callback when state changes.
    var onStateChanged: ((TrimState) -> Void)?

    /// Whether a trim is in progress.
    var isTrimming: Bool { state.isTrimming }

    // MARK: - Context

    /// Update context for collision detection.
    func updateContext(
        clips: [TimelineClip]? = nil,
        viewport: ViewportState? = nil,
        snapTargets: [TimeMicros]? = nil
    ) {
        if let clips { self.allClips = clips }
        if let viewport { self.viewport = viewport }
        if let snapTargets { self.snapTargets = snapTargets }
    }

    // MARK: - Trim Operations

    /// Start a trim operation.
    @discardableResult
    func startTrim(
        clipId: String,
        trimType: TrimType,
        position: CGPoint
    ) -> TrimState {
        guard let clip = allClips.first(where: { $0.id == clipId }) else {
            return .idle
        }

        let edgeTime = trimType == .head ? clip.startTime : clip.endTime

        state = TrimState(
            type: .pending,
            clipId: clipId,
            trimType: trimType,
            startPosition: position,
            currentPosition: position,
            startEdgeTime: edgeTime,
            preview: TrimPreview(
                originalClip: clip,
                previewClip: clip,
                trimType: trimType,
                timeDelta: 0
            ),
            exceededThreshold: false
        )

        notifyStateChanged()
        return state
    }

    /// Update the trim position.
    @discardableResult
    func updateTrim(_ position: CGPoint) -> TrimState {
        guard state.type != .idle else { return state }

        // Check if we've exceeded the threshold
        let delta = position.x - state.startPosition.x
        let exceededThreshold = state.exceededThreshold || abs(delta) > Self.trimThreshold

        let newType: TrimStateType = exceededThreshold ? .trimming : .pending

        // Calculate preview
        let preview = calculatePreview(position)

        // Provide haptic feedback on state transitions
        if !state.exceededThreshold && exceededThreshold {
            UISelectionFeedbackGenerator().selectionChanged()
        }

        // Provide haptic feedback when hitting bounds
        if !state.preview.atBound && preview.atBound {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }

        // Provide haptic feedback on snap
        if preview.hasSnap && !state.preview.hasSnap {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        state = state.with(
            type: newType,
            currentPosition: position,
            preview: preview,
            exceededThreshold: exceededThreshold
        )

        notifyStateChanged()
        return state
    }

    /// End the trim operation.
    @discardableResult
    func endTrim() -> TrimState {
        guard state.type != .idle else { return state }

        if !state.exceededThreshold || !state.preview.isValid {
            return cancelTrim()
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        state = state.with(type: .completed)
        notifyStateChanged()

        let result = state
        state = .idle
        return result
    }

    /// Cancel the trim operation.
    @discardableResult
    func cancelTrim() -> TrimState {
        guard state.type != .idle else { return state }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        state = state.with(type: .cancelled)
        notifyStateChanged()

        let result = state
        state = .idle
        return result
    }

    // MARK: - Preview Calculation

    private func calculatePreview(_ position: CGPoint) -> TrimPreview {
        guard let originalClip = allClips.first(where: { $0.id == state.clipId }) else {
            return .empty
        }

        // Calculate time delta from pixel delta
        let pixelDelta = Double(position.x - state.startPosition.x)
        var timeDelta = TimeMicros((viewport.microsPerPixel * pixelDelta).rounded())

        // Calculate new edge time
        var newEdgeTime = state.startEdgeTime + timeDelta

        // Try snapping
        let (snappedTime, didSnap) = trySnap(newEdgeTime)
        if didSnap {
            newEdgeTime = snappedTime
            timeDelta = newEdgeTime - state.startEdgeTime
        }

        // Apply trim and get validation result
        let (previewClip, validation) = applyTrim(originalClip, trimType: state.trimType, newEdgeTime: newEdgeTime)

        return TrimPreview(
            originalClip: originalClip,
            previewClip: previewClip,
            trimType: state.trimType,
            timeDelta: timeDelta,
            isValid: validation.isValid,
            invalidReason: validation.reason,
            atSourceStart: validation.atSourceStart,
            atSourceEnd: validation.atSourceEnd,
            atMinDuration: validation.atMinDuration,
            snappedTime: didSnap ? snappedTime : nil
        )
    }

    private func trySnap(_ time: TimeMicros) -> (TimeMicros, Bool) {
        guard !snapTargets.isEmpty else { return (time, false) }

        let snapThresholdTime = TimeMicros((viewport.microsPerPixel * Double(Self.snapDistance)).rounded())

        for target in snapTargets {
            let distance = abs(time - target)
            if distance <= snapThresholdTime {
                return (target, true)
            }
        }

        return (time, false)
    }

    private func validateTrim(
        _ original: TimelineClip,
        trimType: TrimType,
        newEdgeTime: TimeMicros
    ) -> TrimValidation {
        var atSourceStart = false
        var atSourceEnd = false
        var atMinDuration = false
        var reason: String?

        if trimType == .head {
            // Head trim - adjusting start time
            let newDuration = original.endTime - newEdgeTime

            // Check minimum duration
            if newDuration < TimelineClip.minDuration {
                atMinDuration = true
                reason = "Minimum duration reached"
            }

            // Check source bounds
            let sourceDelta = newEdgeTime - original.startTime
            let newSourceIn = original.sourceIn + TimeMicros((Double(sourceDelta) * original.speed).rounded())
            if newSourceIn < 0 {
                atSourceStart = true
                reason = "Source start reached"
            }

            // Check collision with previous clip
            if let collision = checkCollisionAtTime(
                clipId: original.id,
                trackId: original.trackId,
                time: newEdgeTime,
                isStart: true
            ) {
                reason = collision
            }
        } else {
            // Tail trim - adjusting end time
            let newDuration = newEdgeTime - original.startTime

            // Check minimum duration
            if newDuration < TimelineClip.minDuration {
                atMinDuration = true
                reason = "Minimum duration reached"
            }

            // Check source bounds (for non-generator clips)
            if !original.isGeneratorClip {
                let newSourceOut = original.sourceIn + TimeMicros((Double(newDuration) * original.speed).rounded())
                if newSourceOut > original.sourceOut + 1_000_000 {
                    atSourceEnd = true
                    reason = "Source end reached"
                }
            }

            // Check collision with next clip
            if let collision = checkCollisionAtTime(
                clipId: original.id,
                trackId: original.trackId,
                time: newEdgeTime,
                isStart: false
            ) {
                reason = collision
            }
        }

        return TrimValidation(
            isValid: reason == nil,
            reason: reason,
            atSourceStart: atSourceStart,
            atSourceEnd: atSourceEnd,
            atMinDuration: atMinDuration
        )
    }

    private func applyTrim(
        _ original: TimelineClip,
        trimType: TrimType,
        newEdgeTime: TimeMicros
    ) -> (TimelineClip, TrimValidation) {
        let validation = validateTrim(original, trimType: trimType, newEdgeTime: newEdgeTime)

        if !validation.isValid {
            let clampedEdgeTime = clampEdgeTime(original, trimType: trimType, requestedTime: newEdgeTime)
            let clampedClip = trimType == .head
                ? original.trimHead(clampedEdgeTime)
                : original.trimTail(clampedEdgeTime)
            return (clampedClip, validation)
        }

        let resultClip = trimType == .head
            ? original.trimHead(newEdgeTime)
            : original.trimTail(newEdgeTime)

        return (resultClip, validation)
    }

    private func clampEdgeTime(
        _ original: TimelineClip,
        trimType: TrimType,
        requestedTime: TimeMicros
    ) -> TimeMicros {
        if trimType == .head {
            let minStartTime = original.endTime - original.sourceDuration
            let maxStartTime = original.endTime - TimelineClip.minDuration

            var clamped = requestedTime
            if clamped < 0 { clamped = 0 }
            if clamped < minStartTime { clamped = minStartTime }
            if clamped > maxStartTime { clamped = maxStartTime }
            return clamped
        } else {
            let minEndTime = original.startTime + TimelineClip.minDuration

            var clamped = requestedTime
            if clamped < minEndTime { clamped = minEndTime }
            return clamped
        }
    }

    private func checkCollisionAtTime(
        clipId: String,
        trackId: String,
        time: TimeMicros,
        isStart: Bool
    ) -> String? {
        for other in allClips {
            guard other.id != clipId else { continue }
            guard other.trackId == trackId else { continue }

            if isStart {
                if time < other.endTime && time >= other.startTime {
                    return "Overlaps with \(other.label ?? other.id)"
                }
            } else {
                if time > other.startTime && time <= other.endTime {
                    return "Overlaps with \(other.label ?? other.id)"
                }
            }
        }
        return nil
    }

    private func notifyStateChanged() {
        onStateChanged?(state)
    }
}
