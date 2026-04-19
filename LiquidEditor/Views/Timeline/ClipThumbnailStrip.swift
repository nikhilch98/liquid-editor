// ClipThumbnailStrip.swift
// LiquidEditor
//
// T7-41: Horizontal thumbnail strip rendering for a clip tile.
//
// Given a clip URL + tile width/height, lays out N tile slots (N =
// width / 60pt, capped at 20) and decodes the underlying video frames
// via `ClipThumbnailCache`. While a frame is loading a gradient
// placeholder is shown; once decoded the `CGImage` is swapped in.
//
// The strip is a leaf view — it owns no state beyond the decoded
// images, so callers can drop it into `ClipView` as a background layer
// without restructuring state.
//
// Pure SwiftUI, iOS 26 native styling.
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.17.

import AVFoundation
import SwiftUI

// MARK: - ClipThumbnailStrip

@MainActor
struct ClipThumbnailStrip: View {

    // MARK: - Input

    /// File URL of the clip's underlying video asset. If `nil` a
    /// placeholder strip is shown (useful for generated / gap clips).
    let clipURL: URL?

    /// Total width of the strip in points.
    let width: CGFloat

    /// Height of the strip (= height of each thumbnail tile).
    let height: CGFloat

    /// Optional clip duration (microseconds). When provided the strip
    /// samples frames evenly across the duration; otherwise it falls
    /// back to sampling across the asset's natural duration.
    var clipDurationMicros: TimeMicros?

    /// Stable clip identifier — used as the cache key namespace so
    /// multiple instances of the same asset don't cross-pollute.
    var clipID: UUID = UUID()

    /// Optional shared cache. Callers should inject a single cache
    /// from `ServiceContainer` to avoid duplicate decode work. When
    /// `nil` a local cache is created and kept for the lifetime of
    /// this view.
    var cache: ClipThumbnailCache?

    // MARK: - Tunables

    /// Target point-width per thumbnail tile. N = width / tileWidth.
    private let tileWidth: CGFloat = 60

    /// Hard cap on thumbnail count. Keeps cache pressure bounded on
    /// very wide (high-zoom) clips.
    private let maxTiles: Int = 20

    // MARK: - State

    @State private var images: [Int: CGImage] = [:]
    @State private var loadTask: Task<Void, Never>?
    @State private var localCache = ClipThumbnailCache()

    /// Native pixel density — used to size thumbnail decode requests
    /// so 1pt maps cleanly to device pixels. Replaces the deprecated
    /// `UIScreen.main.scale` path.
    @Environment(\.displayScale) private var displayScale

    // MARK: - Derived

    private var tileCount: Int {
        let raw = Int((width / tileWidth).rounded(.down))
        return max(1, min(maxTiles, raw))
    }

    private var perTileWidth: CGFloat {
        guard tileCount > 0 else { return width }
        return width / CGFloat(tileCount)
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tileCount, id: \.self) { index in
                thumbnail(at: index)
                    .frame(width: perTileWidth, height: height)
                    .clipped()
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task(id: taskID) {
            await loadThumbnails()
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }

    /// Task identity — changes whenever the strip's inputs change, so
    /// `.task(id:)` re-triggers decode.
    private var taskID: String {
        "\(clipURL?.absoluteString ?? "nil")|\(Int(width))|\(Int(height))|\(clipDurationMicros ?? 0)"
    }

    // MARK: - Single thumbnail slot

    @ViewBuilder
    private func thumbnail(at index: Int) -> some View {
        if let cg = images[index] {
            Image(decorative: cg, scale: 1, orientation: .up)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: perTileWidth, height: height)
                .clipped()
        } else {
            placeholder(at: index)
        }
    }

    @ViewBuilder
    private func placeholder(at index: Int) -> some View {
        // Alternating subtle gradient keeps the strip visually alive
        // while decode is in flight — matches the existing ClipView
        // dark-purple filmstrip placeholder style.
        let isEven = index % 2 == 0
        let top = Color(red: 0.16, green: 0.12, blue: 0.24)
        let bottom = Color(red: 0.10, green: 0.07, blue: 0.16)
        LinearGradient(
            colors: isEven ? [top, bottom] : [bottom, top],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Decode driver

    private func loadThumbnails() async {
        guard let clipURL else { return }
        let activeCache = cache ?? localCache
        let asset = AVURLAsset(url: clipURL)

        // Derive the asset duration once; fall back to `clipDurationMicros`
        // if available and the load fails.
        let durationMicros: TimeMicros
        do {
            let cmDuration = try await asset.load(.duration)
            let micros = TimeMicros(cmDuration.seconds * 1_000_000)
            durationMicros = micros > 0
                ? micros
                : (clipDurationMicros ?? 0)
        } catch {
            durationMicros = clipDurationMicros ?? 0
        }

        guard durationMicros > 0 else { return }

        let count = tileCount
        let scale = max(displayScale, 1)
        let size = CGSize(
            width: perTileWidth * scale,
            height: height * scale
        )

        for index in 0..<count {
            if Task.isCancelled { return }

            // Sample time = midpoint of each tile's slice of duration.
            let fraction = (Double(index) + 0.5) / Double(count)
            let time = TimeMicros(Double(durationMicros) * fraction)

            do {
                let image = try await activeCache.thumbnail(
                    for: clipID,
                    at: time,
                    asset: asset,
                    size: size
                )
                if Task.isCancelled { return }
                images[index] = image
            } catch {
                // Swallow — the placeholder remains visible for this slot.
                continue
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ClipThumbnailStrip(
        clipURL: nil,
        width: 320,
        height: 48,
        clipDurationMicros: 5_000_000
    )
    .padding()
    .background(Color.black)
}
