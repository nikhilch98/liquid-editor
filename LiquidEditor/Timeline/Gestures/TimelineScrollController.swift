// TimelineScrollController.swift
// LiquidEditor
//
// iOS-like friction scrolling for the timeline with momentum physics.
// Uses FrictionSimulation equivalent for natural deceleration.
//

import Foundation
import CoreGraphics
import UIKit

// MARK: - ScrollStateType

/// State of a scroll operation.
enum ScrollStateType: String, Sendable, Equatable {
    /// No scroll in progress.
    case idle
    /// Direct scroll (finger dragging).
    case scrolling
    /// Momentum scroll (finger released with velocity).
    case momentum
    /// Programmatic scroll animation.
    case animating
}

// MARK: - ScrollState

/// State of an ongoing scroll operation.
struct ScrollState: Sendable, Equatable {
    /// Current state type.
    let type: ScrollStateType
    /// Initial scroll position when started.
    let initialScrollPosition: TimeMicros
    /// Current scroll position.
    let currentScrollPosition: TimeMicros
    /// Current velocity (microseconds per second).
    let velocity: Double
    /// Whether we're at the start bound.
    let atStart: Bool
    /// Whether we're at the end bound.
    let atEnd: Bool

    /// Idle state.
    static let idle = ScrollState(
        type: .idle,
        initialScrollPosition: 0,
        currentScrollPosition: 0,
        velocity: 0,
        atStart: false,
        atEnd: false
    )

    /// Whether a scroll is in progress.
    var isScrolling: Bool { type != .idle }

    /// Whether momentum scrolling.
    var hasMomentum: Bool { type == .momentum }

    /// Whether at any bound.
    var atBound: Bool { atStart || atEnd }

    /// Create copy with updated values.
    func with(
        type: ScrollStateType? = nil,
        initialScrollPosition: TimeMicros? = nil,
        currentScrollPosition: TimeMicros? = nil,
        velocity: Double? = nil,
        atStart: Bool? = nil,
        atEnd: Bool? = nil
    ) -> ScrollState {
        ScrollState(
            type: type ?? self.type,
            initialScrollPosition: initialScrollPosition ?? self.initialScrollPosition,
            currentScrollPosition: currentScrollPosition ?? self.currentScrollPosition,
            velocity: velocity ?? self.velocity,
            atStart: atStart ?? self.atStart,
            atEnd: atEnd ?? self.atEnd
        )
    }
}

// MARK: - TimelineScrollController

/// Controller for timeline scroll operations.
///
/// Manages direct scrolling and momentum-based scrolling with iOS-like physics.
@Observable @MainActor
final class TimelineScrollController {

    // MARK: - Scroll Physics Constants

    /// iOS-like friction coefficient.
    ///
    /// 0.135 matches `UIScrollViewDecelerationRateFast` (0.99) in iOS.
    /// Provides natural "flick and coast" feel.
    static let iosFrictionCoefficient: Double = 0.135

    /// Minimum velocity to trigger momentum scrolling (micros/second).
    ///
    /// 100,000 micros/second = 0.1 seconds of timeline per second of real time.
    static let minMomentumVelocity: Double = 100_000.0

    /// Velocity below which momentum scrolling stops.
    ///
    /// 10,000 micros/second = 0.01 seconds of timeline per second.
    /// At this speed, movement is imperceptible.
    static let stoppingVelocity: Double = 10_000.0

    /// Default animation duration for programmatic scrolling.
    static let defaultAnimationDuration: TimeInterval = 0.3

    // MARK: - State

    /// Current scroll state.
    private(set) var state: ScrollState = .idle

    /// Current viewport state.
    private var viewport: ViewportState = .initial()

    /// Maximum scroll position (end of timeline).
    private var maxScrollPosition: TimeMicros = 0

    /// Display link for momentum scrolling.
    private var displayLink: CADisplayLink?

    /// Momentum initial velocity.
    private var momentumVelocity: Double = 0

    /// Momentum initial position.
    private var momentumInitialPosition: Double = 0

    /// Momentum start time.
    private var momentumStartTime: CFTimeInterval?

    /// Callback when state changes.
    var onStateChanged: ((ScrollState) -> Void)?

    /// Callback when viewport should update.
    var onViewportChanged: ((ViewportState) -> Void)?

    /// Whether a scroll is in progress.
    var isScrolling: Bool { state.isScrolling }

    // MARK: - Configuration

    /// Update the current viewport state.
    func updateViewport(_ vp: ViewportState) {
        viewport = vp
    }

    /// Update the maximum scroll position.
    func updateMaxScrollPosition(_ maxPosition: TimeMicros) {
        maxScrollPosition = maxPosition
    }

    // MARK: - Direct Scrolling

    /// Start direct scrolling.
    @discardableResult
    func startScroll() -> ScrollState {
        stopMomentum()

        state = ScrollState(
            type: .scrolling,
            initialScrollPosition: viewport.scrollPosition,
            currentScrollPosition: viewport.scrollPosition,
            velocity: 0,
            atStart: false,
            atEnd: false
        )

        onStateChanged?(state)
        return state
    }

    /// Scroll by pixel delta.
    @discardableResult
    func scroll(_ deltaPixels: Double) -> ViewportState {
        let timeDelta = TimeMicros((deltaPixels * viewport.microsPerPixel).rounded())

        var newPosition = viewport.scrollPosition + timeDelta

        var atStart = false
        var atEnd = false

        if newPosition < 0 {
            newPosition = 0
            atStart = true
        }

        if maxScrollPosition > 0 && newPosition > maxScrollPosition {
            newPosition = maxScrollPosition
            atEnd = true
        }

        // Provide haptic feedback when hitting bounds
        if (atStart || atEnd) && !state.atBound {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        viewport = viewport.withScrollPosition(
            newPosition,
            maxPosition: maxScrollPosition > 0 ? maxScrollPosition : nil
        )

        state = state.with(
            currentScrollPosition: newPosition,
            atStart: atStart,
            atEnd: atEnd
        )

        onStateChanged?(state)
        onViewportChanged?(viewport)

        return viewport
    }

    /// Scroll by time delta directly.
    @discardableResult
    func scrollByTime(_ timeDelta: TimeMicros) -> ViewportState {
        let pixelDelta = Double(timeDelta) / viewport.microsPerPixel
        return scroll(pixelDelta)
    }

    /// End direct scrolling with optional velocity for momentum.
    @discardableResult
    func endScroll(velocityPixelsPerSecond: Double = 0) -> ViewportState {
        guard state.type == .scrolling else { return viewport }

        let velocityMicrosPerSecond = velocityPixelsPerSecond * viewport.microsPerPixel

        // Check if we should start momentum scrolling
        if abs(velocityMicrosPerSecond) > Self.minMomentumVelocity && !state.atBound {
            startMomentumScroll(velocityMicrosPerSecond: velocityMicrosPerSecond)
            return viewport
        }

        // No momentum - return to idle
        state = ScrollState.idle.with(currentScrollPosition: viewport.scrollPosition)
        onStateChanged?(state)
        return viewport
    }

    // MARK: - Momentum Scrolling

    /// Start momentum scrolling with initial velocity.
    func startMomentumScroll(velocityMicrosPerSecond: Double) {
        momentumVelocity = velocityMicrosPerSecond
        momentumInitialPosition = Double(viewport.scrollPosition)
        momentumStartTime = nil

        state = state.with(
            type: .momentum,
            velocity: velocityMicrosPerSecond
        )

        // Start display link
        displayLink?.invalidate()
        displayLink = CADisplayLink(target: MomentumTarget(controller: self), selector: #selector(MomentumTarget.tick(_:)))
        displayLink?.add(to: .main, forMode: .common)

        onStateChanged?(state)
    }

    /// Called on each display link tick.
    fileprivate func onMomentumTick(_ displayLink: CADisplayLink) {
        guard let startTime = momentumStartTime else {
            momentumStartTime = displayLink.timestamp
            return
        }

        let elapsed = displayLink.timestamp - startTime

        // iOS friction simulation: position = v0 / k * (1 - e^(-k*t))
        // velocity = v0 * e^(-k*t)
        let k = 1.0 / Self.iosFrictionCoefficient
        let decay = exp(-k * elapsed)
        let position = momentumInitialPosition + (momentumVelocity / k) * (1.0 - decay)
        let velocity = momentumVelocity * decay

        var newPosition = TimeMicros(position.rounded())

        var atStart = false
        var atEnd = false

        if newPosition < 0 {
            newPosition = 0
            atStart = true
        }

        if maxScrollPosition > 0 && newPosition > maxScrollPosition {
            newPosition = maxScrollPosition
            atEnd = true
        }

        // Haptic feedback when hitting bounds
        if (atStart || atEnd) && !state.atBound {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            stopMomentum()
            return
        }

        // Check if we should stop
        if abs(velocity) < Self.stoppingVelocity {
            stopMomentum()
            return
        }

        viewport = viewport.withScrollPosition(
            newPosition,
            maxPosition: maxScrollPosition > 0 ? maxScrollPosition : nil
        )

        state = state.with(
            currentScrollPosition: newPosition,
            velocity: velocity,
            atStart: atStart,
            atEnd: atEnd
        )

        onViewportChanged?(viewport)
        onStateChanged?(state)
    }

    /// Stop momentum scrolling.
    func stopMomentum() {
        displayLink?.invalidate()
        displayLink = nil
        momentumStartTime = nil

        if state.type == .momentum {
            state = ScrollState.idle.with(currentScrollPosition: viewport.scrollPosition)
            onStateChanged?(state)
        }
    }

    // MARK: - Programmatic Scrolling

    /// Scroll to a specific time position (immediate, no animation).
    @discardableResult
    func scrollToTime(_ time: TimeMicros) -> ViewportState {
        stopMomentum()

        let endPosition = max(0, min(time, maxScrollPosition > 0 ? maxScrollPosition : time))

        viewport = viewport.withScrollPosition(
            endPosition,
            maxPosition: maxScrollPosition > 0 ? maxScrollPosition : nil
        )

        state = ScrollState.idle.with(currentScrollPosition: viewport.scrollPosition)
        onStateChanged?(state)
        onViewportChanged?(viewport)

        return viewport
    }

    /// Center the viewport on a specific time.
    @discardableResult
    func centerOnTime(_ time: TimeMicros) -> ViewportState {
        let centerOffset = TimeMicros((viewport.contentWidth / 2 * viewport.microsPerPixel).rounded())
        let scrollPosition = max(0, time - centerOffset)
        return scrollToTime(scrollPosition)
    }

    /// Scroll to ensure a time is visible (with margin).
    @discardableResult
    func scrollToMakeVisible(_ time: TimeMicros, marginPixels: Double = 50) -> ViewportState {
        let marginTime = TimeMicros((marginPixels * viewport.microsPerPixel).rounded())
        let visibleRange = viewport.visibleTimeRange

        // Check if already visible with margin
        if time >= visibleRange.start + marginTime && time <= visibleRange.end - marginTime {
            return viewport
        }

        // Calculate new scroll position
        let newScrollPosition: TimeMicros
        if time < visibleRange.start + marginTime {
            newScrollPosition = max(0, time - marginTime)
        } else {
            newScrollPosition = max(0, time - (viewport.visibleDuration - marginTime))
        }

        return scrollToTime(newScrollPosition)
    }

    // MARK: - Cleanup

    /// Dispose of resources.
    func dispose() {
        stopMomentum()
    }

    // Note: Call dispose() explicitly before this object is deallocated.
    // deinit cannot access @MainActor-isolated properties in Swift 6 strict concurrency.
}

// MARK: - MomentumTarget

/// Helper class to bridge CADisplayLink's target-action with the controller.
/// CADisplayLink requires an NSObject target.
private final class MomentumTarget: NSObject {
    weak var controller: TimelineScrollController?

    init(controller: TimelineScrollController) {
        self.controller = controller
    }

    @MainActor
    @objc func tick(_ link: CADisplayLink) {
        controller?.onMomentumTick(link)
    }
}
