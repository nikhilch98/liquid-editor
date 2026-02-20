// ClipReorderOverlay.swift
// LiquidEditor
//
// Full-screen overlay that activates during clip reorder mode.
// Renders all clips on a track as equal-sized thumbnail cards in a
// horizontal strip. The dragged card floats above the others with
// scale(1.05) and shadow. A vertical insertion-indicator line shows
// where the clip will land on drop.
//
// Matches Flutter ClipReorderOverlay:
// - Frosted-glass backdrop fades in/out with .easeInOut(duration: 0.2)
// - Cards animate to their target slot with AnimatablePosition
// - Dragged card follows dragPosition, slightly elevated
// - Haptic selection click on insertion index change
//
// Pure SwiftUI, iOS 26 native styling.
// Swift 6 strict concurrency: all state is @MainActor via the View.

import SwiftUI
import UIKit

// MARK: - ClipReorderOverlay

/// Full-screen overlay that lets the user reorder clips by dragging.
///
/// Place this as a ZStack overlay on top of the timeline. Pass the
/// current drag position from the parent's DragGesture.
///
/// - Parameters:
///   - clips:             All clips on the track, sorted by startTime (gaps excluded).
///   - draggedClipId:     ID of the clip that was long-pressed to initiate reorder.
///   - dragPosition:      Current drag X position in the overlay's coordinate space.
///   - isActive:          Controls the fade-in / fade-out animation of the overlay.
///   - onReorderComplete: Called with the new clip-ID order when the user releases.
///   - onReorderCancelled: Called when the drag ends with no change.
struct ClipReorderOverlay: View {

    // MARK: - Inputs

    let clips: [TimelineClip]
    let draggedClipId: String
    let dragPosition: CGPoint
    let isActive: Bool
    let onReorderComplete: ([String]) -> Void
    let onReorderCancelled: () -> Void

    // MARK: - Local State

    /// Insertion index where the dragged card will land (0 = before first slot).
    @State private var insertionIndex: Int = 0

    // MARK: - Layout Constants

    private static let cardGap: CGFloat = 6
    private static let cardCornerRadius: CGFloat = 10
    private static let maxCardWidth: CGFloat = 80
    private static let horizontalPadding: CGFloat = 16
    private static let durationLabelHeight: CGFloat = 20
    private static let dragScale: CGFloat = 1.05
    private static let dragElevation: CGFloat = 10
    private static let backdropBlur: CGFloat = 20
    private static let backdropOpacity: Double = 0.65
    private static let animationDuration: Double = 0.2
    private static let insertionLineWidth: CGFloat = 2
    private static let insertionLineOpacity: Double = 0.85

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let layout = computeLayout(in: geo.size)

            ZStack {
                // Frosted glass backdrop
                backdropLayer

                // Non-dragged cards
                ForEach(layout.renderOrder.indices, id: \.self) { idx in
                    let clipId = layout.renderOrder[idx]
                    let slotIndex = idx >= insertionIndex ? idx + 1 : idx
                    let targetX = layout.stripLeft + CGFloat(slotIndex) * (layout.cardWidth + Self.cardGap)

                    if let clip = clipFor(id: clipId) {
                        ReorderCard(
                            clip: clip,
                            width: layout.cardWidth,
                            height: layout.cardHeight,
                            cornerRadius: Self.cardCornerRadius,
                            isElevated: false
                        )
                        .frame(width: layout.cardWidth, height: layout.cardHeight + Self.durationLabelHeight)
                        .animation(.easeInOut(duration: Self.animationDuration), value: slotIndex)
                        .position(
                            x: targetX + layout.cardWidth / 2,
                            y: layout.stripTop + (layout.cardHeight + Self.durationLabelHeight) / 2
                        )
                    }
                }

                // Insertion indicator line
                insertionIndicator(layout: layout)

                // Dragged card (rendered on top)
                if let draggedClip = clipFor(id: draggedClipId) {
                    ReorderCard(
                        clip: draggedClip,
                        width: layout.cardWidth,
                        height: layout.cardHeight,
                        cornerRadius: Self.cardCornerRadius,
                        isElevated: true
                    )
                    .frame(width: layout.cardWidth, height: layout.cardHeight + Self.durationLabelHeight)
                    .scaleEffect(Self.dragScale)
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                    .position(
                        x: dragPosition.x,
                        y: layout.stripTop + (layout.cardHeight + Self.durationLabelHeight) / 2 - Self.dragElevation
                    )
                }
            }
            .opacity(isActive ? 1 : 0)
            .animation(.easeInOut(duration: Self.animationDuration), value: isActive)
            .onChange(of: dragPosition) { _, newPos in
                let layout = computeLayout(in: geo.size)
                let newIndex = calculateInsertionIndex(dragX: newPos.x, layout: layout)
                if newIndex != insertionIndex {
                    insertionIndex = newIndex
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onChange(of: isActive) { _, active in
                // When overlay deactivates, commit the current insertion order.
                if !active {
                    commitReorder()
                }
            }
            .onAppear {
                // Initialize insertion index to the dragged clip's original position.
                if let idx = clips.firstIndex(where: { $0.id == draggedClipId }) {
                    insertionIndex = idx
                }
            }
        }
    }

    // MARK: - Backdrop

    private var backdropLayer: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .background(Color.black.opacity(Self.backdropOpacity))
            .ignoresSafeArea()
    }

    // MARK: - Insertion Indicator

    @ViewBuilder
    private func insertionIndicator(layout: ReorderLayout) -> some View {
        let lineX = layout.stripLeft + CGFloat(insertionIndex) * (layout.cardWidth + Self.cardGap) - Self.cardGap / 2
        let lineHeight = layout.cardHeight + Self.durationLabelHeight + 8

        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(Color.accentColor.opacity(Self.insertionLineOpacity))
            .frame(width: Self.insertionLineWidth, height: lineHeight)
            .position(
                x: lineX,
                y: layout.stripTop + lineHeight / 2 - 4
            )
            .animation(.easeInOut(duration: Self.animationDuration), value: insertionIndex)
    }

    // MARK: - Layout Computation

    private struct ReorderLayout {
        let cardWidth: CGFloat
        let cardHeight: CGFloat
        let stripLeft: CGFloat
        let stripTop: CGFloat
        /// Clip IDs in render order (excluding the dragged clip).
        let renderOrder: [String]
    }

    private func computeLayout(in size: CGSize) -> ReorderLayout {
        let availableWidth = size.width - (Self.horizontalPadding * 2)
        let count = clips.count

        // Card width: fill available space, capped at maxCardWidth
        let totalGaps = CGFloat(max(count - 1, 0)) * Self.cardGap
        let cardWidth = count > 0
            ? ((availableWidth - totalGaps) / CGFloat(count)).clamped(to: 40...Self.maxCardWidth)
            : Self.maxCardWidth
        let cardHeight = cardWidth  // Square cards

        let stripWidth = CGFloat(count) * cardWidth + CGFloat(max(count - 1, 0)) * Self.cardGap
        let stripLeft = (size.width - stripWidth) / 2
        let stripTop = (size.height - cardHeight - Self.durationLabelHeight) / 2

        // Render order excludes the dragged clip
        let renderOrder = clips
            .map(\.id)
            .filter { $0 != draggedClipId }

        return ReorderLayout(
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            stripLeft: stripLeft,
            stripTop: stripTop,
            renderOrder: renderOrder
        )
    }

    // MARK: - Insertion Index Calculation

    private func calculateInsertionIndex(dragX: CGFloat, layout: ReorderLayout) -> Int {
        let totalCardWidth = layout.cardWidth + Self.cardGap
        let relativeX = dragX - layout.stripLeft
        let index = Int((relativeX / totalCardWidth).rounded())
        return index.clamped(to: 0...(clips.count - 1))
    }

    // MARK: - Helpers

    private func clipFor(id: String) -> TimelineClip? {
        clips.first(where: { $0.id == id })
    }

    // MARK: - Commit

    /// Builds the final clip order and notifies the parent.
    ///
    /// Called automatically when `isActive` transitions to `false`.
    private func commitReorder() {
        var newOrder = clips.map(\.id)
        newOrder.removeAll { $0 == draggedClipId }
        let target = insertionIndex.clamped(to: 0...newOrder.count)
        newOrder.insert(draggedClipId, at: target)

        let originalOrder = clips.map(\.id)
        if newOrder == originalOrder {
            onReorderCancelled()
        } else {
            onReorderComplete(newOrder)
        }
    }
}

// MARK: - ReorderCard

/// Individual square thumbnail card shown in the reorder strip.
private struct ReorderCard: View {

    let clip: TimelineClip
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let isElevated: Bool

    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail / placeholder
            thumbnailView
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            isElevated ? Color.accentColor : Color.secondary.opacity(0.4),
                            lineWidth: isElevated ? 2 : 0.5
                        )
                )

            // Duration label
            Text(formatDuration(clip.duration))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        // Color placeholder matching clip type
        ZStack {
            clipColor
            Image(systemName: iconForClipType(clip.type))
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var clipColor: Color {
        let v = clip.clipColorValue
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }

    private func iconForClipType(_ type: ClipType) -> String {
        switch type {
        case .video:  "film"
        case .audio:  "waveform"
        case .image:  "photo"
        case .text:   "textformat"
        case .gap:    "square.dashed"
        case .color:  "rectangle.fill"
        case .effect: "sparkles"
        }
    }

    // MARK: - Duration Formatting

    private func formatDuration(_ micros: TimeMicros) -> String {
        let seconds = Double(micros) / 1_000_000
        if seconds < 10 {
            return String(format: "%.1fs", seconds)
        }
        return String(format: "%.0fs", seconds)
    }
}

// MARK: - Comparable+clamped

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("ClipReorderOverlay") {
    let sampleClips = [
        TimelineClip(
            id: "c1", mediaAssetId: nil, trackId: "t1", type: .video,
            startTime: 0, duration: 3_000_000, clipColorValue: 0xFF5856D6, label: "Clip 1"
        ),
        TimelineClip(
            id: "c2", mediaAssetId: nil, trackId: "t1", type: .video,
            startTime: 3_000_000, duration: 2_000_000, clipColorValue: 0xFFAF52DE, label: "Clip 2"
        ),
        TimelineClip(
            id: "c3", mediaAssetId: nil, trackId: "t1", type: .audio,
            startTime: 5_000_000, duration: 4_000_000, clipColorValue: 0xFF34C759, label: "Audio"
        ),
    ]

    ZStack {
        Color.black.ignoresSafeArea()
        ClipReorderOverlay(
            clips: sampleClips,
            draggedClipId: "c1",
            dragPosition: CGPoint(x: 200, y: 300),
            isActive: true,
            onReorderComplete: { _ in },
            onReorderCancelled: {}
        )
    }
}
#endif
