// ScopesPanel.swift
// LiquidEditor
//
// C5-9: Scopes panel for color grading — Histogram, Waveform,
// Vectorscope, Parade. Floating Liquid Glass panel with a tab
// picker and Canvas-based rendering at ~30 Hz.
//
// Rendering is driven by a 1/30s Timer that refreshes TimelineDate.now,
// causing the Canvas to redraw with the latest frame statistics.
//
// Frame data is supplied by `ScopesEngine` — this is a stub today
// (C5-12 will wire in live frame extraction from PlaybackEngine).

import SwiftUI
import Foundation

// MARK: - ScopeKind

/// Which scope is currently visible.
enum ScopeKind: String, CaseIterable, Identifiable, Sendable {
    case histogram
    case waveform
    case vectorscope
    case parade

    var id: String { rawValue }

    var label: String {
        switch self {
        case .histogram: "Histogram"
        case .waveform: "Waveform"
        case .vectorscope: "Vectorscope"
        case .parade: "Parade"
        }
    }

    var symbol: String {
        switch self {
        case .histogram: "chart.bar.fill"
        case .waveform: "waveform"
        case .vectorscope: "circle.hexagongrid.fill"
        case .parade: "chart.bar.doc.horizontal"
        }
    }
}

// MARK: - ScopesFrameStats

/// Frame statistics used to render all four scope types.
///
/// All histograms are 256 bins; luminance waveform/parade rows are
/// flattened into 256×N arrays. Vectorscope points are unit-range
/// (x,y) pairs centered around (0.5, 0.5).
struct ScopesFrameStats: Sendable, Equatable {
    /// Red channel histogram (256 bins, normalized 0..1).
    let red: [Double]
    /// Green channel histogram (256 bins, normalized 0..1).
    let green: [Double]
    /// Blue channel histogram (256 bins, normalized 0..1).
    let blue: [Double]
    /// Luminance histogram (256 bins, normalized 0..1).
    let luminance: [Double]

    /// Luminance waveform rows: each row is 256 column intensities.
    let waveformRows: [[Double]]

    /// Vectorscope samples in unit-square coordinates (x,y in 0..1).
    let vectorscopeSamples: [CGPoint]

    /// Identity/empty frame with blank histograms.
    static let empty = ScopesFrameStats(
        red: Array(repeating: 0, count: 256),
        green: Array(repeating: 0, count: 256),
        blue: Array(repeating: 0, count: 256),
        luminance: Array(repeating: 0, count: 256),
        waveformRows: [],
        vectorscopeSamples: []
    )
}

// MARK: - ScopesEngine

/// Supplies frame statistics to the `ScopesPanel`.
///
/// This is a stub: returns deterministic mock data derived from the
/// current time so the UI is alive. C5-12 will replace this with a
/// real pull from the playback pipeline.
@MainActor
@Observable
final class ScopesEngine {
    /// Latest computed stats for the currently visible frame.
    private(set) var latestStats: ScopesFrameStats = .empty

    /// Refresh stats using the current wall-clock time as a seed.
    ///
    /// Call at up to 30 Hz from a `Timer` driver.
    func refresh() {
        latestStats = Self.mockStats(seed: Date().timeIntervalSinceReferenceDate)
    }

    /// Produce a deterministic mock `ScopesFrameStats`.
    ///
    /// The distributions oscillate with `seed` so the UI visibly animates
    /// even without real frame input.
    private static func mockStats(seed: Double) -> ScopesFrameStats {
        let phase = seed.truncatingRemainder(dividingBy: 10.0) / 10.0
        var red = [Double](repeating: 0, count: 256)
        var green = [Double](repeating: 0, count: 256)
        var blue = [Double](repeating: 0, count: 256)
        var lum = [Double](repeating: 0, count: 256)

        for i in 0..<256 {
            let t = Double(i) / 255.0
            red[i] = gauss(t, mu: 0.45 + 0.1 * phase, sigma: 0.18)
            green[i] = gauss(t, mu: 0.50, sigma: 0.20)
            blue[i] = gauss(t, mu: 0.55 - 0.1 * phase, sigma: 0.17)
            lum[i] = gauss(t, mu: 0.50, sigma: 0.22)
        }

        normalize(&red)
        normalize(&green)
        normalize(&blue)
        normalize(&lum)

        // Mock waveform: 72 rows x 256 cols, each row a smoothed luminance strip.
        let rowCount = 72
        var rows = [[Double]]()
        rows.reserveCapacity(rowCount)
        for row in 0..<rowCount {
            var cols = [Double](repeating: 0, count: 256)
            for col in 0..<256 {
                let x = Double(col) / 255.0
                let y = Double(row) / Double(rowCount - 1)
                let v = gauss(x, mu: 0.5 + 0.2 * sin((y + phase) * .pi * 2), sigma: 0.06)
                cols[col] = v
            }
            rows.append(cols)
        }

        // Mock vectorscope: 360 polar samples clustered near center.
        var samples = [CGPoint]()
        samples.reserveCapacity(360)
        for i in 0..<360 {
            let theta = Double(i) / 360.0 * .pi * 2.0 + phase * .pi
            let r = 0.18 + 0.10 * sin(theta * 3 + phase * 6)
            let cx = 0.5 + r * cos(theta)
            let cy = 0.5 + r * sin(theta)
            samples.append(CGPoint(x: cx, y: cy))
        }

        return ScopesFrameStats(
            red: red,
            green: green,
            blue: blue,
            luminance: lum,
            waveformRows: rows,
            vectorscopeSamples: samples
        )
    }

    private static func gauss(_ x: Double, mu: Double, sigma: Double) -> Double {
        let dx = x - mu
        return exp(-(dx * dx) / (2 * sigma * sigma))
    }

    private static func normalize(_ arr: inout [Double]) {
        let m = arr.max() ?? 1.0
        guard m > 0 else { return }
        for i in 0..<arr.count { arr[i] /= m }
    }
}

// MARK: - ScopesPanel

/// Floating scopes panel with four selectable scope types.
///
/// Tab picker at top switches between Histogram / Waveform /
/// Vectorscope / Parade. The Canvas redraws at ~30 Hz via a
/// `TimelineView` whose schedule is a `PeriodicTimelineSchedule`
/// with a 1/30s interval.
@MainActor
struct ScopesPanel: View {
    @State private var kind: ScopeKind = .histogram
    @State private var engine = ScopesEngine()

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            header
            scopeView
        }
        .padding(LiquidSpacing.md)
        .frame(width: 320, height: 260)
        .glassEffect(style: .thin, cornerRadius: LiquidSpacing.cornerLarge)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack {
            Image(systemName: kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Picker("Scope", selection: $kind) {
                ForEach(ScopeKind.allCases) { k in
                    Text(k.label).tag(k)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Scope type")
        }
    }

    // MARK: - Scope Canvas

    @ViewBuilder
    private var scopeView: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in
            Canvas { ctx, size in
                engine.refresh()
                let stats = engine.latestStats
                drawScope(stats: stats, in: ctx, size: size)
            }
            .accessibilityHidden(true)
            .background(
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall, style: .continuous)
                    .fill(Color.black.opacity(0.25))
            )
        }
    }

    private func drawScope(stats: ScopesFrameStats, in ctx: GraphicsContext, size: CGSize) {
        switch kind {
        case .histogram:
            drawHistogram(stats: stats, in: ctx, size: size)
        case .waveform:
            drawWaveform(stats: stats, in: ctx, size: size)
        case .vectorscope:
            drawVectorscope(stats: stats, in: ctx, size: size)
        case .parade:
            drawParade(stats: stats, in: ctx, size: size)
        }
    }

    // MARK: - Histogram

    private func drawHistogram(stats: ScopesFrameStats, in ctx: GraphicsContext, size: CGSize) {
        let channels: [(values: [Double], color: Color)] = [
            (stats.red, Color.red.opacity(0.6)),
            (stats.green, Color.green.opacity(0.6)),
            (stats.blue, Color.blue.opacity(0.6)),
        ]
        for channel in channels {
            var path = Path()
            let bins = channel.values.count
            guard bins > 1 else { continue }
            path.move(to: CGPoint(x: 0, y: size.height))
            for i in 0..<bins {
                let x = CGFloat(i) / CGFloat(bins - 1) * size.width
                let y = size.height - CGFloat(channel.values[i]) * size.height
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            ctx.fill(path, with: .color(channel.color))
        }
    }

    // MARK: - Waveform (luminance)

    private func drawWaveform(stats: ScopesFrameStats, in ctx: GraphicsContext, size: CGSize) {
        let rows = stats.waveformRows
        guard !rows.isEmpty else { return }
        let rowCount = rows.count
        let cols = rows[0].count
        guard cols > 0 else { return }

        let cellW = size.width / CGFloat(cols)
        let cellH = size.height / CGFloat(rowCount)

        for r in 0..<rowCount {
            for c in 0..<cols {
                let v = rows[r][c]
                guard v > 0.05 else { continue }
                let rect = CGRect(
                    x: CGFloat(c) * cellW,
                    y: CGFloat(r) * cellH,
                    width: cellW + 0.5,
                    height: cellH + 0.5
                )
                ctx.fill(Path(rect), with: .color(.green.opacity(v * 0.8)))
            }
        }
    }

    // MARK: - Vectorscope

    private func drawVectorscope(stats: ScopesFrameStats, in ctx: GraphicsContext, size: CGSize) {
        let minDim = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = minDim / 2 - 8

        // Reference circle
        let circleRect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        ctx.stroke(
            Path(ellipseIn: circleRect),
            with: .color(.white.opacity(0.25)),
            lineWidth: 1
        )

        // Crosshairs
        var cross = Path()
        cross.move(to: CGPoint(x: center.x - radius, y: center.y))
        cross.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        cross.move(to: CGPoint(x: center.x, y: center.y - radius))
        cross.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        ctx.stroke(cross, with: .color(.white.opacity(0.15)), lineWidth: 0.5)

        // Samples
        for pt in stats.vectorscopeSamples {
            let px = (pt.x - 0.5) * 2.0 * radius + center.x
            let py = (pt.y - 0.5) * 2.0 * radius + center.y
            let dot = CGRect(x: px - 1.0, y: py - 1.0, width: 2.0, height: 2.0)
            ctx.fill(Path(ellipseIn: dot), with: .color(.yellow.opacity(0.7)))
        }
    }

    // MARK: - Parade (R/G/B columns)

    private func drawParade(stats: ScopesFrameStats, in ctx: GraphicsContext, size: CGSize) {
        let columnWidth = size.width / 3.0
        let columns: [(values: [Double], color: Color)] = [
            (stats.red, .red),
            (stats.green, .green),
            (stats.blue, .blue),
        ]
        for (idx, col) in columns.enumerated() {
            let origin = CGFloat(idx) * columnWidth
            let bins = col.values.count
            guard bins > 1 else { continue }
            var path = Path()
            path.move(to: CGPoint(x: origin, y: size.height))
            for i in 0..<bins {
                let x = origin + CGFloat(i) / CGFloat(bins - 1) * columnWidth
                let y = size.height - CGFloat(col.values[i]) * size.height
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: origin + columnWidth, y: size.height))
            path.closeSubpath()
            ctx.fill(path, with: .color(col.color.opacity(0.6)))
        }

        // Separators
        var sep = Path()
        sep.move(to: CGPoint(x: columnWidth, y: 0))
        sep.addLine(to: CGPoint(x: columnWidth, y: size.height))
        sep.move(to: CGPoint(x: columnWidth * 2, y: 0))
        sep.addLine(to: CGPoint(x: columnWidth * 2, y: size.height))
        ctx.stroke(sep, with: .color(.white.opacity(0.2)), lineWidth: 0.5)
    }
}

// MARK: - Preview

#Preview {
    ScopesPanel()
        .padding()
        .background(Color.black)
}
