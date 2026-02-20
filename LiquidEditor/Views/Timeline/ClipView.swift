// ClipView.swift
// LiquidEditor
//
// Individual clip rendered on the timeline — shows uniform dark purple
// background with a thumbnail strip for video/image clips, name with
// dark badge, trim handles in gold with grip lines, keyframe markers,
// selection state, and supports drag/trim gestures with haptic feedback.
//
// Thumbnail strip behavior:
// - Video/image clips attempt to tile real frames loaded from ThumbnailCache.
// - While thumbnails are loading, a gradient placeholder is shown (matches
//   Flutter: alternating dark-purple gradient tiles across the clip width).
// - Thumbnails are requested every ~60pt of clip width, capped at 20.
// - Loaded UIImages are stored in @State so views stay lightweight.
//
// Pure SwiftUI, iOS 26 native styling.
// Matches Flutter TimelineClipWidget layout.

import SwiftUI
import UIKit

// MARK: - ClipView

struct ClipView: View {

    // MARK: - Properties

    /// The timeline item to render.
    let item: any TimelineItemProtocol

    /// Width in points (calculated from duration * zoom).
    let width: CGFloat

    /// Height in points.
    let height: CGFloat

    /// Whether this clip is currently selected.
    let isSelected: Bool

    /// Whether this clip is currently being dragged.
    let isDragging: Bool

    /// Keyframe positions as fractions (0.0 - 1.0) of clip duration.
    let keyframePositions: [Double]

    /// Optional real audio waveform amplitude samples (0.0 - 1.0).
    /// If provided, these values are used for bar heights instead of pseudo-random generation.
    let waveformSamples: [Float]?

    // MARK: - Callbacks

    var onTap: (() -> Void)?
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?
    var onTrimStartChanged: ((CGFloat) -> Void)?
    var onTrimEndChanged: ((CGFloat) -> Void)?
    var onTrimEnded: (() -> Void)?

    // Context menu actions
    var onSplit: (() -> Void)?
    var onDelete: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var onSpeed: (() -> Void)?
    var onVolume: (() -> Void)?

    // MARK: - Thumbnail Support

    /// Optional ThumbnailCache injected from the parent (TimelineView).
    ///
    /// When provided and the item is a VideoClip or ImageClip, the clip body
    /// shows a tiled strip of real video frames instead of the gradient placeholder.
    var thumbnailCache: ThumbnailCache? = nil

    // MARK: - Local State

    @State private var dragOffset: CGFloat = 0

    /// Loaded thumbnail frames, keyed by slot index. Populated asynchronously.
    @State private var loadedThumbnails: [Int: UIImage] = [:]

    // MARK: - Constants

    /// Uniform clip background color (dark purple #1A1A3E).
    private let clipColor = Color(red: 0.1, green: 0.1, blue: 0.24)

    /// Gold selection / trim handle color (#FFD700).
    private let goldColor = Color(red: 1, green: 0.84, blue: 0)

    /// Unselected border color.
    private let defaultBorderColor = Color(red: 0.25, green: 0.25, blue: 0.63).opacity(0.6)

    private let trimHandleWidth: CGFloat = 32
    private let cornerRadius: CGFloat = 6
    private let minWidthForLabel: CGFloat = 40
    private let minWidthForTrimHandles: CGFloat = 40

    // MARK: - Initializer

    init(
        item: any TimelineItemProtocol,
        width: CGFloat,
        height: CGFloat,
        isSelected: Bool,
        isDragging: Bool = false,
        keyframePositions: [Double] = [],
        waveformSamples: [Float]? = nil,
        thumbnailCache: ThumbnailCache? = nil,
        onTap: (() -> Void)? = nil,
        onDragChanged: ((CGFloat) -> Void)? = nil,
        onDragEnded: (() -> Void)? = nil,
        onTrimStartChanged: ((CGFloat) -> Void)? = nil,
        onTrimEndChanged: ((CGFloat) -> Void)? = nil,
        onTrimEnded: (() -> Void)? = nil,
        onSplit: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onDuplicate: (() -> Void)? = nil,
        onSpeed: (() -> Void)? = nil,
        onVolume: (() -> Void)? = nil
    ) {
        self.item = item
        self.width = width
        self.height = height
        self.isSelected = isSelected
        self.isDragging = isDragging
        self.keyframePositions = keyframePositions
        self.waveformSamples = waveformSamples
        self.thumbnailCache = thumbnailCache
        self.onTap = onTap
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        self.onTrimStartChanged = onTrimStartChanged
        self.onTrimEndChanged = onTrimEndChanged
        self.onTrimEnded = onTrimEnded
        self.onSplit = onSplit
        self.onDelete = onDelete
        self.onDuplicate = onDuplicate
        self.onSpeed = onSpeed
        self.onVolume = onVolume
    }

    // MARK: - Clip Type Detection

    /// Whether the current item is an audio clip.
    private var isAudioClip: Bool {
        item is AudioClip
    }

    /// Whether the current item is a video or image clip that should show thumbnails.
    private var isVideoOrImageClip: Bool {
        item is VideoClip || item is ImageClip
    }

    /// Media asset ID for thumbnail loading, if available.
    private var mediaAssetId: String? {
        if let vc = item as? VideoClip { return vc.mediaAssetId }
        if let ic = item as? ImageClip { return ic.mediaAssetId }
        return nil
    }

    /// Source in-point in microseconds, used to anchor thumbnail time offsets.
    private var sourceInMicros: TimeMicros {
        if let vc = item as? VideoClip { return vc.sourceInMicros }
        return 0
    }

    // MARK: - Thumbnail Constants

    /// Approximate point width per thumbnail slot (used to decide slot count).
    private static let thumbnailSlotTargetWidth: CGFloat = 60

    /// Maximum number of thumbnail slots to request.
    private static let maxThumbnailSlots: Int = 20

    /// Target thumbnail pixel width (at 2x screen scale).
    private static let thumbnailPixelWidth: Int = 120

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .leading) {
            // Main clip body.
            clipBody

            // Thumbnail strip for video/image clips (rendered above background,
            // below overlays). Shows real frames when loaded, gradient otherwise.
            if isVideoOrImageClip {
                thumbnailStrip
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }

            // Waveform overlay for audio clips.
            if isAudioClip {
                waveformOverlay
            }

            // Keyframe markers.
            keyframeMarkers

            // Clip name with dark badge.
            clipLabel

            // Trim handles (visible when selected and clip is wide enough).
            if isSelected && width > minWidthForTrimHandles {
                trimHandles
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .offset(x: dragOffset)
        .shadow(
            color: isDragging ? .black.opacity(0.3) : .clear,
            radius: isDragging ? 12 : 0,
            y: isDragging ? 4 : 0
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        .onTapGesture {
            onTap?()
        }
        .gesture(clipDragGesture)
        .task(id: item.id) {
            await loadThumbnailsIfNeeded()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Clip: \(item.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Double-tap and hold to drag. Use context menu for more options." : "Tap to select")
        .contextMenu {
            Button {
                onSplit?()
            } label: {
                Label("Split", systemImage: "scissors")
            }

            Button {
                onDuplicate?()
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }

            Button {
                onSpeed?()
            } label: {
                Label("Speed", systemImage: "gauge.open.with.lines.needle.33percent")
            }

            Button {
                onVolume?()
            } label: {
                Label("Volume", systemImage: "speaker.wave.2")
            }

            Divider()

            Button(role: .destructive) {
                onDelete?()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Thumbnail Strip

    /// Tiled thumbnail strip for video/image clips.
    ///
    /// When real frames are loaded they replace the gradient placeholders slot
    /// by slot as they arrive from the cache.
    private var thumbnailStrip: some View {
        let slotCount = thumbnailSlotCount()
        let slotWidth = thumbnailSlotPointWidth(slotCount: slotCount)

        return HStack(spacing: 0) {
            ForEach(0..<slotCount, id: \.self) { slot in
                if let image = loadedThumbnails[slot] {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: slotWidth, height: height)
                        .clipped()
                        .allowsHitTesting(false)
                } else {
                    // Gradient placeholder — matches Flutter's alternating blue-purple tiles.
                    let baseAlpha = 0.5 + Double(slot % 4) * 0.1
                    let accentAlpha = 0.4 + Double(slot % 3) * 0.12

                    LinearGradient(
                        colors: [
                            Color(red: 0.23, green: 0.23, blue: 0.49).opacity(baseAlpha),
                            Color(red: 0.16, green: 0.16, blue: 0.37).opacity(accentAlpha),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: slotWidth, height: height)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(width: width, height: height, alignment: .leading)
    }

    /// Number of thumbnail slots to request for the current clip width.
    private func thumbnailSlotCount() -> Int {
        let natural = Int(ceil(width / Self.thumbnailSlotTargetWidth))
        return natural.clamped(to: 2...Self.maxThumbnailSlots)
    }

    /// Width of each thumbnail slot so they tile evenly across the clip.
    private func thumbnailSlotPointWidth(slotCount: Int) -> CGFloat {
        guard slotCount > 0 else { return width }
        return width / CGFloat(slotCount)
    }

    /// Asynchronously loads thumbnails from the ThumbnailCache for each slot.
    ///
    /// Called via `.task(id: item.id)` so it cancels and restarts when the
    /// item changes. All cache access is awaited on the actor; results are
    /// applied to @State on the MainActor.
    @MainActor
    private func loadThumbnailsIfNeeded() async {
        guard isVideoOrImageClip,
              let cache = thumbnailCache,
              let assetId = mediaAssetId else { return }

        let slotCount = thumbnailSlotCount()
        let durationMicros = item.durationMicroseconds
        guard durationMicros > 0, slotCount > 0 else { return }

        let stepMicros = durationMicros / Int64(slotCount)

        for slot in 0..<slotCount {
            guard !Task.isCancelled else { break }

            let timeMicros = sourceInMicros + Int64(slot) * stepMicros
            let image = await cache.getThumbnail(
                assetId: assetId,
                timeMicros: timeMicros,
                width: Self.thumbnailPixelWidth
            )

            if let image {
                loadedThumbnails[slot] = image
            }
        }
    }

    // MARK: - Waveform Overlay

    /// Waveform bars for audio clips.
    ///
    /// When `waveformSamples` is provided, those real amplitude values drive
    /// the bar heights. Otherwise, a seeded pseudo-random generator with
    /// low-frequency variation and smoothing produces a realistic-looking
    /// waveform pattern.
    private var waveformOverlay: some View {
        Canvas { context, size in
            let barCount = max(Int(width / 3), 50)
            let barWidth: CGFloat = max(width / CGFloat(barCount) * 0.55, 1.5)
            let barSpacing = width / CGFloat(barCount)

            // Compute normalized heights (0.0 - 1.0) for each bar.
            let heights: [Double] = computeWaveformHeights(barCount: barCount)

            for i in 0..<barCount {
                let normalizedHeight = heights[i]
                let barHeight = max(size.height * 0.15, size.height * normalizedHeight * 0.85)
                let x = CGFloat(i) * barSpacing + barSpacing / 2
                let y = (size.height - barHeight) / 2

                let rect = CGRect(x: x - barWidth / 2, y: y, width: barWidth, height: barHeight)

                // Gradient fill: darker at bottom, lighter at top.
                let gradientRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .linearGradient(
                        Gradient(colors: [
                            .white.opacity(0.15),
                            .white.opacity(0.4),
                        ]),
                        startPoint: CGPoint(x: gradientRect.midX, y: gradientRect.maxY),
                        endPoint: CGPoint(x: gradientRect.midX, y: gradientRect.minY)
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }

    /// Compute waveform bar heights.
    ///
    /// If `waveformSamples` are available, resample them to the requested bar count.
    /// Otherwise, generate pseudo-random heights with multi-frequency variation
    /// and neighbor smoothing for a more realistic look.
    private func computeWaveformHeights(barCount: Int) -> [Double] {
        if let samples = waveformSamples, !samples.isEmpty {
            return resampleWaveform(samples, to: barCount)
        }
        return generatePseudoRandomHeights(barCount: barCount)
    }

    /// Resample real waveform data to the target bar count using linear interpolation.
    private func resampleWaveform(_ samples: [Float], to count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard samples.count > 1 else {
            return Array(repeating: Double(samples.first ?? 0), count: count)
        }

        var result = [Double](repeating: 0, count: count)
        let ratio = Double(samples.count - 1) / Double(max(count - 1, 1))

        for i in 0..<count {
            let position = Double(i) * ratio
            let lower = Int(position)
            let upper = min(lower + 1, samples.count - 1)
            let fraction = position - Double(lower)
            let value = Double(samples[lower]) * (1.0 - fraction) + Double(samples[upper]) * fraction
            result[i] = min(max(value, 0), 1)
        }
        return result
    }

    /// Generate pseudo-random heights with multi-frequency variation and smoothing.
    ///
    /// Combines a low-frequency "bass envelope" with higher-frequency detail
    /// using a seeded LCG, then applies neighbor smoothing for natural appearance.
    private func generatePseudoRandomHeights(barCount: Int) -> [Double] {
        guard barCount > 0 else { return [] }

        // Seeded linear congruential generator for deterministic output.
        var lcgState = UInt64(truncatingIfNeeded: item.displayName.hashValue &+ 0x5DEECE66D)

        func nextRandom() -> Double {
            lcgState = lcgState &* 6364136223846793005 &+ 1442695040888963407
            return Double((lcgState >> 33) & 0x7FFFFFFF) / Double(0x7FFFFFFF)
        }

        var raw = [Double](repeating: 0, count: barCount)

        for i in 0..<barCount {
            let t = Double(i) / Double(max(barCount - 1, 1))

            // Low-frequency envelope (bass pattern) -- slow undulation.
            let lowFreq = 0.5 + 0.3 * sin(t * .pi * 3.2 + 0.7)

            // Mid-frequency variation -- gives structure.
            let midFreq = 0.5 + 0.2 * sin(t * .pi * 8.5 + 1.3)

            // High-frequency noise from seeded RNG.
            let noise = nextRandom()

            // Blend: 35% low-freq envelope, 25% mid-freq, 40% noise.
            let blended = lowFreq * 0.35 + midFreq * 0.25 + noise * 0.40

            // Clamp to valid range.
            raw[i] = min(max(blended, 0.08), 1.0)
        }

        // Smooth adjacent bars for natural transitions.
        var smoothed = [Double](repeating: 0, count: barCount)
        for i in 0..<barCount {
            let prev = i > 0 ? raw[i - 1] : raw[i]
            let next = i < barCount - 1 ? raw[i + 1] : raw[i]
            smoothed[i] = prev * 0.2 + raw[i] * 0.6 + next * 0.2
        }

        return smoothed
    }

    // MARK: - Clip Body

    private var clipBody: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(clipColor.opacity(isDragging ? 0.6 : 0.8))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        isSelected ? goldColor : defaultBorderColor,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
    }

    // MARK: - Clip Label

    @ViewBuilder
    private var clipLabel: some View {
        if width > minWidthForLabel {
            VStack {
                HStack {
                    Text(item.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, LiquidSpacing.xs)
                        .padding(.vertical, LiquidSpacing.xxs)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.black.opacity(0.5))
                        )
                        .padding(.leading, LiquidSpacing.sm)
                        .padding(.top, LiquidSpacing.xs)

                    Spacer()
                }
                Spacer()
            }
            .accessibilityHidden(true)
        }
    }

    // MARK: - Keyframe Markers

    @ViewBuilder
    private var keyframeMarkers: some View {
        if !keyframePositions.isEmpty && width > 0 {
            ForEach(Array(keyframePositions.enumerated()), id: \.offset) { _, position in
                let xPos = CGFloat(position) * width

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                    .rotationEffect(.degrees(45))
                    .overlay(
                        Rectangle()
                            .strokeBorder(Color.black.opacity(0.3), lineWidth: 1)
                            .rotationEffect(.degrees(45))
                    )
                    .shadow(color: .black.opacity(0.3), radius: 4)
                    .position(x: xPos, y: height / 2)
            }
        }
    }

    // MARK: - Trim Handles

    @ViewBuilder
    private var trimHandles: some View {
        HStack(spacing: 0) {
            // Left (start) trim handle.
            trimHandle(isStart: true)
                .gesture(trimStartGesture)

            Spacer()

            // Right (end) trim handle.
            trimHandle(isStart: false)
                .gesture(trimEndGesture)
        }
    }

    /// Gold trim handle with 3 vertical grip lines.
    private func trimHandle(isStart: Bool) -> some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: isStart ? cornerRadius : 0,
                bottomLeadingRadius: isStart ? cornerRadius : 0,
                bottomTrailingRadius: isStart ? 0 : cornerRadius,
                topTrailingRadius: isStart ? 0 : cornerRadius
            )
            .fill(goldColor)
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

            // Three vertical grip lines.
            VStack(spacing: LiquidSpacing.xxs) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 2, height: 12)
                }
            }
        }
        .frame(width: trimHandleWidth, height: height)
        .accessibilityLabel(isStart ? "Trim start handle" : "Trim end handle")
        .accessibilityHint("Drag to trim clip \(isStart ? "start" : "end")")
    }

    // MARK: - Gestures

    /// Drag gesture for moving the clip.
    private var clipDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                dragOffset = value.translation.width
                onDragChanged?(value.translation.width)
            }
            .onEnded { _ in
                dragOffset = 0
                onDragEnded?()
            }
    }

    /// Drag gesture for trimming the start edge with haptic feedback.
    private var trimStartGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if abs(value.translation.width) < 4 {
                    // Trim start: selection click haptic
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                onTrimStartChanged?(value.translation.width)
            }
            .onEnded { _ in
                // Trim end: medium impact haptic
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onTrimEnded?()
            }
    }

    /// Drag gesture for trimming the end edge with haptic feedback.
    private var trimEndGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if abs(value.translation.width) < 4 {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                onTrimEndChanged?(value.translation.width)
            }
            .onEnded { _ in
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onTrimEnded?()
            }
    }
}

// MARK: - Comparable+clamped (ClipView private)

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
