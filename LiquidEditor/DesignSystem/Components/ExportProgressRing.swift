// ExportProgressRing.swift
// LiquidEditor
//
// PP12-5: Export progress ring driven by CADisplayLink for smooth
// 60 fps interpolation between discrete progress updates.
//
// The ring takes a target `progress: Double` as input. A private
// `DisplayLink` object ticks at display cadence (`.common` run
// loop mode) and eases an internal `displayed` value toward the
// target. When the two converge and `progress >= 1.0`, the
// display link is stopped. This matches the spec §10.7 guidance:
// "Export ring animation: CADisplayLink at 60 Hz; avoid SwiftUI
// `.animation` re-renders."

import QuartzCore
import SwiftUI

// MARK: - DisplayLink (public-ish helper kept file-private)

/// Thin `@MainActor` observable wrapper around `CADisplayLink`.
///
/// Exposes a `value: Double` that smoothly eases toward a target.
/// All state mutation happens on the main actor since both SwiftUI
/// and `CADisplayLink` live there.
///
/// Scope: file-private — the ring is the only consumer for now.
/// If another surface needs it, promote to a dedicated file.
@MainActor
@Observable
fileprivate final class DisplayLink {

    // MARK: - Public state

    /// Current eased value in `0...1`.
    private(set) var value: Double = 0

    /// Whether the link is currently firing.
    private(set) var isRunning: Bool = false

    // MARK: - Internal state

    /// Target value the link eases toward.
    private var target: Double = 0

    /// The underlying display link (nil when stopped).
    private var link: CADisplayLink?

    /// Retained bridge NSObject — CADisplayLink needs an @objc
    /// selector target. Holding the bridge here keeps the ring
    /// itself free of NSObject baggage.
    private var tickTarget: DisplayLinkTickTarget?

    /// Easing coefficient per tick. 0.18 produces a visibly smooth
    /// follow that reaches 99% convergence in ~25 frames (~0.4s)
    /// — snappy but not jittery.
    private let easing: Double = 0.18

    // MARK: - API

    /// Update the target value. Starts the link if not already
    /// running. Caller is responsible for calling `stop()` when
    /// the view disappears or the render completes.
    func setTarget(_ target: Double) {
        self.target = max(0, min(1, target))
        if !isRunning {
            start()
        }
    }

    /// Jump immediately without animation. Use for project
    /// switches or when progress resets to 0.
    func snap(to value: Double) {
        let clamped = max(0, min(1, value))
        self.value = clamped
        self.target = clamped
    }

    /// Stop ticking and release the link. Idempotent.
    func stop() {
        link?.invalidate()
        link = nil
        tickTarget = nil
        isRunning = false
    }

    // MARK: - Internals

    private func start() {
        guard link == nil else { return }
        let bridge = DisplayLinkTickTarget { [weak self] in
            self?.tick()
        }
        let link = CADisplayLink(
            target: bridge,
            selector: #selector(DisplayLinkTickTarget.tick)
        )
        link.add(to: .main, forMode: .common)
        self.tickTarget = bridge
        self.link = link
        self.isRunning = true
    }

    private func tick() {
        let delta = target - value
        if abs(delta) < 0.0005 {
            // Snap to exact target; stop if we've reached 100%.
            value = target
            if target >= 0.9999 {
                stop()
            }
            return
        }
        value += delta * easing
    }
}

// MARK: - Bridge NSObject

/// NSObject shim required by `CADisplayLink`'s @objc selector API.
/// Mirrors the pattern in `TimelinePlayheadController.swift`.
@MainActor
private final class DisplayLinkTickTarget: NSObject {
    private let callback: @MainActor () -> Void

    init(callback: @escaping @MainActor () -> Void) {
        self.callback = callback
    }

    @objc func tick() {
        callback()
    }
}

// MARK: - ExportProgressRing

/// Circular progress ring used by the export screen + live activity
/// mirror. Uses a `CADisplayLink`-backed eased follower so the arc
/// sweeps smoothly between discrete progress events from the
/// exporter (typically one update per 5–10%).
///
/// - Parameters:
///   - progress: Target export progress in `0...1`.
///   - etaSeconds: Optional ETA shown below the percentage. Pass
///     `nil` to hide.
///   - diameter: Outer ring diameter in pt. Defaults to 160.
@MainActor
struct ExportProgressRing: View {

    // MARK: - Inputs

    let progress: Double
    let etaSeconds: TimeInterval?
    let diameter: CGFloat

    // MARK: - State

    @State private var link = DisplayLink()

    // MARK: - Init

    init(
        progress: Double,
        etaSeconds: TimeInterval? = nil,
        diameter: CGFloat = 160
    ) {
        self.progress = progress
        self.etaSeconds = etaSeconds
        self.diameter = diameter
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            ringCanvas
            centerLabel
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Export progress")
        .accessibilityValue(accessibilityValueText)
        .task(id: progress) {
            link.setTarget(progress)
        }
        .onDisappear {
            link.stop()
        }
    }

    // MARK: - Subviews

    private var ringCanvas: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)
            let lineWidth: CGFloat = 8
            // Track
            let track = Path(ellipseIn: rect)
            context.stroke(
                track,
                with: .color(.white.opacity(0.08)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            // Progress arc
            let eased = max(0, min(1, link.value))
            guard eased > 0 else { return }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2
            let startAngle = Angle.degrees(-90)
            let endAngle = Angle.degrees(-90 + 360 * eased)
            var arc = Path()
            arc.addArc(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: false
            )
            context.stroke(
                arc,
                with: .color(Color(red: 0.902, green: 0.702, blue: 0.251)), // amber
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
        }
    }

    private var centerLabel: some View {
        VStack(spacing: 4) {
            Text("\(Int((link.value * 100).rounded()))%")
                .font(.system(size: diameter * 0.22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
            if let eta = etaSeconds {
                Text(Self.formatETA(eta))
                    .font(.system(size: diameter * 0.09, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityValueText: String {
        let pct = Int((progress * 100).rounded())
        if let eta = etaSeconds {
            return "\(pct) percent, \(Self.formatETA(eta)) remaining"
        }
        return "\(pct) percent"
    }

    // MARK: - Helpers

    /// Format ETA as `m:ss` or `ss` if under a minute.
    private static func formatETA(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let secs = total % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, secs)
        }
        return "\(secs)s"
    }
}

// MARK: - Preview

#Preview("ExportProgressRing") {
    VStack(spacing: 24) {
        ExportProgressRing(progress: 0.35, etaSeconds: 42)
        ExportProgressRing(progress: 0.78, etaSeconds: 12, diameter: 120)
        ExportProgressRing(progress: 1.0, etaSeconds: nil, diameter: 96)
    }
    .padding()
    .background(Color.black)
}
