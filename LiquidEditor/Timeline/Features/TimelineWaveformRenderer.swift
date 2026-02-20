// TimelineWaveformRenderer.swift
// LiquidEditor
//
// Waveform renderer for drawing audio waveforms on timeline clips.
// Renders cached waveform data as a symmetrical amplitude visualization
// inside clip rectangles. Supports multiple LOD levels for efficient
// rendering at different zoom levels.
//

import Foundation
import CoreGraphics
import SwiftUI

// MARK: - WaveformStyle

/// Style configuration for waveform rendering.
struct WaveformStyle: Equatable, Sendable {
    /// Color of the waveform fill.
    let color: CGColor

    /// Opacity of the waveform.
    let opacity: Double

    /// Whether this is a placeholder (extraction in progress).
    let isPlaceholder: Bool

    /// Animation value for placeholder pulsing (0.0 - 1.0).
    let placeholderAnimationValue: Double

    init(
        color: CGColor = CGColor(red: 0.204, green: 0.78, blue: 0.349, alpha: 1.0), // #34C759
        opacity: Double = 0.6,
        isPlaceholder: Bool = false,
        placeholderAnimationValue: Double = 0.0
    ) {
        self.color = color
        self.opacity = opacity
        self.isPlaceholder = isPlaceholder
        self.placeholderAnimationValue = placeholderAnimationValue
    }

    static let defaults = WaveformStyle()
    static let placeholder = WaveformStyle(isPlaceholder: true)
}

// MARK: - TimelineWaveformRenderer

/// Renders audio waveforms on timeline clips.
///
/// The waveform is drawn as a filled symmetrical path centered vertically
/// within the provided clip rect. For audio clips, it fills the full height.
/// For video clips with audio, it occupies the bottom 30%.
enum TimelineWaveformRenderer {

    // MARK: - CGContext Rendering

    /// Draw waveform into a CGContext.
    ///
    /// - Parameters:
    ///   - context: The graphics context to draw into.
    ///   - path: Pre-computed waveform CGPath.
    ///   - style: Waveform style configuration.
    ///   - size: The available size for rendering.
    static func draw(
        in context: CGContext,
        path: CGPath?,
        style: WaveformStyle = .defaults,
        size: CGSize
    ) {
        if style.isPlaceholder {
            drawPlaceholder(in: context, style: style, size: size)
            return
        }

        guard let path else { return }

        context.saveGState()
        context.setFillColor(style.color.copy(alpha: style.opacity) ?? style.color)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()
    }

    /// Draw a placeholder bar during waveform extraction.
    private static func drawPlaceholder(
        in context: CGContext,
        style: WaveformStyle,
        size: CGSize
    ) {
        let pulseOpacity = 0.15 + 0.15 * style.placeholderAnimationValue

        context.saveGState()
        context.setFillColor(style.color.copy(alpha: pulseOpacity) ?? style.color)

        let midY = size.height / 2
        let barHeight = size.height * 0.3
        let rect = CGRect(
            x: 0,
            y: midY - barHeight / 2,
            width: size.width,
            height: barHeight
        )
        let path = CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()
    }

    // MARK: - Path Building

    /// Build a waveform CGPath from raw sample data.
    ///
    /// - Parameters:
    ///   - samples: Normalized amplitude values (0.0 - 1.0).
    ///   - clipRect: The rectangle to render the waveform in.
    ///   - isAudioClip: If true, fill the full clip height.
    ///     If false (video clip), fill bottom 30%.
    /// - Returns: A filled path representing the symmetrical waveform.
    static func buildWaveformPath(
        samples: [Float],
        clipRect: CGRect,
        isAudioClip: Bool = true
    ) -> CGPath {
        guard !samples.isEmpty else { return CGMutablePath() }

        let waveformRect: CGRect
        if isAudioClip {
            waveformRect = clipRect.insetBy(dx: 2, dy: 2)
        } else {
            waveformRect = CGRect(
                x: clipRect.minX,
                y: clipRect.maxY - clipRect.height * 0.3,
                width: clipRect.width,
                height: clipRect.height * 0.3 - 2
            )
        }

        let midY = waveformRect.midY
        let maxAmplitude = waveformRect.height / 2
        let width = waveformRect.width

        guard width > 0, maxAmplitude > 0 else { return CGMutablePath() }

        let samplesPerPixel = Double(samples.count) / width

        // Build top and bottom points
        var topPoints: [CGPoint] = []
        var bottomPoints: [CGPoint] = []

        var px = 0.0
        while px < width {
            let sampleIdx = Int((px * samplesPerPixel).rounded())
            let endIdx = min(Int(((px + 1) * samplesPerPixel).rounded()), samples.count)

            var peak: Float = 0
            for i in sampleIdx..<min(endIdx, samples.count) {
                let v = abs(samples[i])
                if v > peak { peak = v }
            }

            let x = waveformRect.minX + px
            let amplitude = Double(peak) * maxAmplitude
            topPoints.append(CGPoint(x: x, y: midY - amplitude))
            bottomPoints.append(CGPoint(x: x, y: midY + amplitude))

            px += 1.0
        }

        guard !topPoints.isEmpty else { return CGMutablePath() }

        // Build path
        let path = CGMutablePath()

        // Start at midY
        path.move(to: CGPoint(x: topPoints[0].x, y: midY))

        // Draw top half left to right
        for point in topPoints {
            path.addLine(to: point)
        }

        // Draw bottom half right to left (mirror)
        for point in bottomPoints.reversed() {
            path.addLine(to: point)
        }

        path.closeSubpath()
        return path
    }

    /// Build a waveform path for a specific clip's visible region.
    ///
    /// - Parameters:
    ///   - samples: Full waveform samples for the media asset.
    ///   - sourceIn: Source in point (microseconds).
    ///   - sourceOut: Source out point (microseconds).
    ///   - durationMicros: Total source duration (microseconds).
    ///   - clipRect: The clip's rectangle on screen.
    ///   - isAudioClip: Whether this is a dedicated audio clip.
    static func buildClipWaveformPath(
        samples: [Float],
        sourceIn: TimeMicros,
        sourceOut: TimeMicros,
        durationMicros: TimeMicros,
        clipRect: CGRect,
        isAudioClip: Bool = true
    ) -> CGPath {
        guard !samples.isEmpty, durationMicros > 0 else { return CGMutablePath() }

        let samplesPerMicro = Double(samples.count) / Double(durationMicros)
        let startSample = min(max(Int((Double(sourceIn) * samplesPerMicro).rounded()), 0), samples.count)
        let endSample = min(max(Int((Double(sourceOut) * samplesPerMicro).rounded()), 0), samples.count)
        let visibleSampleCount = endSample - startSample

        guard visibleSampleCount > 0 else { return CGMutablePath() }

        // Extract visible samples
        let visibleSamples = Array(samples[startSample..<endSample])

        return buildWaveformPath(
            samples: visibleSamples,
            clipRect: clipRect,
            isAudioClip: isAudioClip
        )
    }
}

// MARK: - SwiftUI Canvas Integration

/// A SwiftUI view that renders a waveform using Canvas.
struct WaveformCanvasView: View {
    let samples: [Float]
    let clipRect: CGRect
    let isAudioClip: Bool
    let style: WaveformStyle

    init(
        samples: [Float],
        clipRect: CGRect,
        isAudioClip: Bool = true,
        style: WaveformStyle = .defaults
    ) {
        self.samples = samples
        self.clipRect = clipRect
        self.isAudioClip = isAudioClip
        self.style = style
    }

    var body: some View {
        Canvas { context, size in
            if style.isPlaceholder {
                // Draw placeholder
                let pulseOpacity = 0.15 + 0.15 * style.placeholderAnimationValue
                let midY = size.height / 2
                let barHeight = size.height * 0.3
                let rect = CGRect(
                    x: 0,
                    y: midY - barHeight / 2,
                    width: size.width,
                    height: barHeight
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 2),
                    with: .color(Color(cgColor: style.color).opacity(pulseOpacity))
                )
            } else if !samples.isEmpty {
                let path = TimelineWaveformRenderer.buildWaveformPath(
                    samples: samples,
                    clipRect: CGRect(origin: .zero, size: size),
                    isAudioClip: isAudioClip
                )
                let swiftUIPath = Path(path)
                context.fill(
                    swiftUIPath,
                    with: .color(Color(cgColor: style.color).opacity(style.opacity))
                )
            }
        }
        .frame(width: clipRect.width, height: clipRect.height)
    }
}
