// TimelineTileRenderer.swift
// LiquidEditor
//
// PP12-4: Tile-based timeline render planner.
//
// Produces a list of `TimelineTile` descriptors for a visible
// timeline range. A "tile" is a fixed horizontal slice of the
// timeline that the UI layer will render as an image (thumbnail
// strip, waveform slab, or ruler segment).
//
// This file is DATA ONLY. It decides where tiles begin and end and
// at what resolution they should be rendered; the actual drawing
// and caching is the caller's responsibility (the timeline view
// typically pairs this planner with `ClipThumbnailCache` /
// `OffMainThumbnailDecoder` for real pixels).
//
// Units — all public doubles are in **seconds (absolute)**. Do
// not pass `TimeMicros` (Int64 microseconds) directly; convert at
// the boundary: `Double(micros) / 1_000_000`.

import Foundation

// MARK: - TileResolution

/// What kind of content a tile represents. Determines decode
/// strategy and cache partition on the UI side.
enum TileResolution: Sendable, Equatable {
    /// Filmstrip tile with N thumbnails per tile.
    case thumbnails(per: Int)
    /// Audio waveform peak-bucket tile.
    case waveformPeaks
    /// Ruler segment (ticks + labels).
    case ruler
}

// MARK: - TimelineTile

/// A single tile descriptor.
///
/// Tiles are identified by stable integer index within the tiling —
/// `id == n` means the nth tile starting from the beginning of the
/// visible range, snapped to tile-width boundaries. This makes
/// tiles diffable with SwiftUI's `ForEach` and lets the UI reuse
/// tiles across scroll events when zoom is stable.
struct TimelineTile: Identifiable, Sendable, Equatable {
    let id: Int
    let startSec: Double
    let endSec: Double
    let resolution: TileResolution

    /// Tile duration in seconds. Always > 0.
    var durationSec: Double { endSec - startSec }
}

// MARK: - TimelineTileRenderer

/// Actor-isolated tile planner. Stateless today (planner only);
/// actor isolation gives us a natural seam for a future tile
/// cache without leaking mutability into the caller.
actor TimelineTileRenderer {

    // MARK: - Tuning

    /// Target on-screen tile width in seconds, per zoom band. The
    /// planner rounds the caller's requested tile width toward the
    /// closest band so adjacent calls with similar zoom hit the
    /// same tile boundaries (tile-reuse across re-renders).
    private static let tileBandsSec: [Double] = [
        0.1,    // very zoomed in — sub-second
        0.25,
        0.5,
        1.0,
        2.0,
        5.0,
        10.0,
        30.0,
        60.0,   // zoomed way out — minute-tiles
    ]

    // MARK: - Init

    init() {}

    // MARK: - API

    /// Plan the tiles covering a visible timeline range.
    ///
    /// - Parameters:
    ///   - visibleRange: The inclusive range the user currently sees
    ///     in seconds (absolute timeline time).
    ///   - tileWidthSec: The caller's preferred tile width in
    ///     seconds. The planner snaps this to the nearest tile band
    ///     so zoom changes within the same band share tile IDs.
    ///   - kind: What to render in each tile.
    /// - Returns: Ordered tiles covering `visibleRange`. Tile `n`'s
    ///   start time is `n * snappedWidth` so the tiling is stable
    ///   across scroll events.
    func renderTiles(
        visibleRange: ClosedRange<Double>,
        tileWidthSec: Double,
        kind: TileResolution
    ) -> [TimelineTile] {
        let width = Self.snapToBand(tileWidthSec)
        guard width > 0 else { return [] }

        let lower = visibleRange.lowerBound
        let upper = visibleRange.upperBound
        guard upper > lower else { return [] }

        // First tile whose end is strictly greater than `lower`.
        let firstID = Int((lower / width).rounded(.down))
        // Last tile whose start is strictly less than `upper`.
        let lastID = Int(((upper / width) - 1e-9).rounded(.down))
        guard lastID >= firstID else { return [] }

        var tiles: [TimelineTile] = []
        tiles.reserveCapacity(lastID - firstID + 1)
        for id in firstID...lastID {
            let start = Double(id) * width
            let end = start + width
            tiles.append(
                TimelineTile(
                    id: id,
                    startSec: start,
                    endSec: end,
                    resolution: kind
                )
            )
        }
        return tiles
    }

    // MARK: - Band snapping

    /// Snap an arbitrary tile width to the nearest band value.
    /// Choosing log-nearest keeps zoom changes stable — widths in
    /// the same bucket produce the same tile IDs.
    nonisolated static func snapToBand(_ requested: Double) -> Double {
        guard requested.isFinite, requested > 0 else { return 0 }
        // Pick the band minimizing |log(band) - log(requested)|.
        let logReq = log(requested)
        var best = tileBandsSec.first ?? requested
        var bestDist = abs(log(best) - logReq)
        for band in tileBandsSec.dropFirst() {
            let dist = abs(log(band) - logReq)
            if dist < bestDist {
                best = band
                bestDist = dist
            }
        }
        return best
    }
}
